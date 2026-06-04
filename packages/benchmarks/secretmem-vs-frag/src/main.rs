#[cfg(not(target_os = "linux"))]
compile_error!("This benchmark only supports Linux.");

mod fragmenter;

use anyhow::{Context, Result, anyhow, bail};
use fragmenter::MemoryFragmenter;
use nix::errno::Errno;
use nix::sys::mman::{MapFlags, ProtFlags, mmap};
use nix::sys::resource::{Resource, getrlimit, setrlimit};
use nix::unistd::{SysconfVar, ftruncate, sysconf};
use std::ffi::c_void;
use std::io::{BufRead, BufReader, Write};
use std::num::NonZeroUsize;
use std::os::fd::{FromRawFd, OwnedFd, RawFd};
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Stdio};
use std::ptr::{self, NonNull};

// libc::SYS_memfd_secret is 447 on x86_64
const SYS_MEMFD_SECRET: libc::c_long = 447;

fn set_oom_score() {
    // Set OOM score to 1000 to be first in line for OOM killer.
    // This is best-effort, so we ignore errors but print warnings.
    match std::fs::File::create("/proc/self/oom_score_adj") {
        Ok(mut f) => {
            if let Err(e) = f.write_all(b"1000") {
                eprintln!("Warning: Failed to write to oom_score_adj: {}", e);
            }
        }
        Err(e) => {
            eprintln!("Warning: Failed to open oom_score_adj: {}", e);
        }
    }
}

fn protect_runner_oom_score(warn: bool) {
    match std::fs::File::create("/proc/self/oom_score_adj") {
        Ok(mut f) => {
            if let Err(e) = f.write_all(b"-1000") {
                if warn {
                    eprintln!(
                        "Warning: Failed to protect runner from OOM (failed to write to oom_score_adj): {}",
                        e
                    );
                }
            } else {
                println!("Runner OOM protection enabled (oom_score_adj set to -1000).");
            }
        }
        Err(e) => {
            if warn {
                eprintln!(
                    "Warning: Failed to protect runner from OOM (failed to open oom_score_adj): {}",
                    e
                );
            }
        }
    }
}

fn set_fd_limit() {
    // Try to increase the FD limit to the maximum allowed.
    // This is best-effort, so we ignore errors.
    match getrlimit(Resource::RLIMIT_NOFILE) {
        Ok((_soft, hard)) => {
            if let Err(e) = setrlimit(Resource::RLIMIT_NOFILE, hard, hard) {
                eprintln!("Warning: Failed to set FD limit: {}", e);
            }
        }
        Err(e) => {
            eprintln!("Warning: Failed to get FD limit: {}", e);
        }
    }
}

fn memfd_secret() -> nix::Result<OwnedFd> {
    let fd = unsafe { libc::syscall(libc::SYS_memfd_secret, 0) };
    if fd < 0 {
        return Err(Errno::last());
    }
    // Safe because we just created this FD and own it.
    unsafe { Ok(OwnedFd::from_raw_fd(fd as RawFd)) }
}

fn allocate_secret_chunk(chunk_size: usize) -> Result<(OwnedFd, NonNull<c_void>)> {
    let fd = memfd_secret().context("memfd_secret failed")?;

    let length = chunk_size as libc::off_t;
    ftruncate(&fd, length).context("ftruncate failed")?;

    let length_nz = NonZeroUsize::new(chunk_size).context("chunk_size must be non-zero")?;

    let addr = unsafe {
        mmap(
            None,
            length_nz,
            ProtFlags::PROT_READ | ProtFlags::PROT_WRITE,
            MapFlags::MAP_SHARED | MapFlags::MAP_POPULATE,
            &fd,
            0,
        )
    }
    .context("mmap failed")?;

    Ok((fd, addr))
}

fn populate_memory(addr: NonNull<c_void>, size: usize) -> Result<()> {
    // Explicitly write to each page to ensure it's backed by physical memory.
    // Use multiple threads to speed this up, similar to page_alloc_bench.
    let num_threads = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1);

    let page_size = sysconf(SysconfVar::PAGE_SIZE)
        .context("Failed to get page size via sysconf")?
        .context("PAGE_SIZE is not supported by this system")? as usize;

    let chunk_ptr = addr.as_ptr() as usize;

    std::thread::scope(|s| {
        let chunk_per_thread = size / num_threads;
        for t in 0..num_threads {
            let start_offset = t * chunk_per_thread;
            let end_offset = if t == num_threads - 1 {
                size
            } else {
                (t + 1) * chunk_per_thread
            };
            s.spawn(move || {
                for offset in (start_offset..end_offset).step_by(page_size) {
                    unsafe {
                        ptr::write_volatile((chunk_ptr + offset) as *mut u8, 0);
                    }
                }
            });
        }
    });
    Ok(())
}

fn worker(chunk_size_mib: usize) -> Result<()> {
    set_oom_score();
    set_fd_limit();

    let chunk_size = chunk_size_mib * 1024 * 1024;
    let mut total_allocated: u64 = 0;
    let mut chunks = Vec::new();

    loop {
        let (fd, addr) = allocate_secret_chunk(chunk_size).with_context(|| {
            format!(
                "Allocation failed after {} MiB",
                total_allocated / (1024 * 1024)
            )
        })?;

        populate_memory(addr, chunk_size).context("Failed to populate memory")?;

        total_allocated += chunk_size as u64;
        chunks.push((fd, addr));
        println!("{}", total_allocated);
        std::io::stdout()
            .flush()
            .context("Failed to flush stdout")?;
    }
}

fn run_once(chunk_size_mib: usize) -> Result<u64> {
    let mut child =
        Command::new(std::env::current_exe().context("Failed to get current executable path")?)
            .arg("--worker")
            .arg("--size-mib")
            .arg(chunk_size_mib.to_string())
            .stdout(Stdio::piped())
            .spawn()
            .context("Failed to spawn worker")?;

    let stdout = child
        .stdout
        .take()
        .context("Failed to open worker stdout")?;
    let reader = BufReader::new(stdout);
    let mut last_allocated_bytes: u64 = 0;
    let mut last_printed_mib: u64 = 0;
    let print_interval_mib = 128;

    for line in reader.lines() {
        let l = line.context("Failed to read line from worker stdout")?;
        if let Ok(bytes) = l.trim().parse::<u64>() {
            last_allocated_bytes = bytes;
            let current_mib = last_allocated_bytes / (1024 * 1024);
            if current_mib - last_printed_mib >= print_interval_mib {
                println!("Progress: {} MiB", current_mib);
                last_printed_mib = current_mib;
            }
        }
    }

    let status = child.wait().context("Failed to wait for worker")?;

    if let Some(signal) = status.signal() {
        println!(
            "Worker killed by signal {} after allocating {} MiB",
            signal,
            last_allocated_bytes / (1024 * 1024)
        );
        if signal == 9 {
            println!("Likely OOM killed.");
            if last_allocated_bytes == 0 {
                bail!("Worker allocated 0 memory before being killed.");
            }
            Ok(last_allocated_bytes)
        } else {
            bail!("Worker killed by unexpected signal: {}", signal);
        }
    } else {
        let code = status.code().unwrap_or(-1);
        bail!(
            "Worker failed with status {} after allocating {} MiB",
            code,
            last_allocated_bytes / (1024 * 1024)
        );
    }
}

fn write_metric(out_dir: &str, run: usize, allocated_bytes: u64) -> Result<()> {
    let dir = std::path::Path::new(out_dir);
    if !dir.exists() {
        std::fs::create_dir_all(dir).context("Failed to create output directory")?;
    }
    let file_path = dir.join(format!("secretmem_vs_frag_run_{}.json", run));
    let mut file = std::fs::File::create(&file_path)
        .with_context(|| format!("Failed to create metric file {:?}", file_path))?;

    let json_content = format!("{{\n  \"allocated_bytes\": {}\n}}\n", allocated_bytes);

    file.write_all(json_content.as_bytes())
        .with_context(|| format!("Failed to write to metric file {:?}", file_path))?;
    Ok(())
}

fn write_summary(
    out_dir: &str,
    antagonized: bool,
    iterations: usize,
    chunk_size_mib: usize,
) -> Result<()> {
    let dir = std::path::Path::new(out_dir);
    if !dir.exists() {
        std::fs::create_dir_all(dir).context("Failed to create output directory")?;
    }
    let file_path = dir.join("secretmem_vs_frag_summary.json");
    let mut file = std::fs::File::create(&file_path)
        .with_context(|| format!("Failed to create summary file {:?}", file_path))?;

    let json_content = format!(
        "{{\n  \"antagonized\": {},\n  \"iterations\": {},\n  \"chunk_size_mib\": {}\n}}\n",
        antagonized, iterations, chunk_size_mib
    );

    file.write_all(json_content.as_bytes())
        .with_context(|| format!("Failed to write to summary file {:?}", file_path))?;
    Ok(())
}

fn runner(chunk_size_mib: usize, iterations: usize, antagonize: bool) -> Result<()> {
    protect_runner_oom_score(antagonize);
    let mut baseline_high_order = 0;

    if antagonize {
        println!("--- Recording Baseline Memory State ---");
        baseline_high_order = fragmenter::count_high_order_free_blocks()
            .context("Failed to count baseline high-order blocks")?;
        println!(
            "Baseline free blocks of size >= 2MB: {}",
            baseline_high_order
        );
        fragmenter::print_buddyinfo_summary()?;
    }

    let _fragmenter = if antagonize {
        println!("--- Initializing Memory Antagonist (Physical Fragmentation) ---");
        // Target 90% of free memory. 90% is highly effective and safer than 96%.
        let frag = MemoryFragmenter::antagonize(0.9)
            .context("Failed to antagonize memory (fragmenter failed)")?;

        println!("--- Verifying Memory State after Antagonist Initialization ---");
        let post_high_order = fragmenter::count_high_order_free_blocks()
            .context("Failed to count post-fragmentation high-order blocks")?;
        println!(
            "Post-fragmentation free blocks of size >= 2MB: {}",
            post_high_order
        );
        fragmenter::print_buddyinfo_summary()?;

        // Verification Rules:
        // 1. If baseline was already fully fragmented (0 blocks), we pass.
        // 2. We expect at least an 80% reduction in high-order blocks.
        // 3. Or, the absolute count of remaining high-order blocks must be very low (< 20 blocks).
        if baseline_high_order > 0 {
            let reduction =
                (baseline_high_order as f64 - post_high_order as f64) / baseline_high_order as f64;
            println!(
                "Verification: High-order block reduction: {:.1}%",
                reduction * 100.0
            );

            if reduction < 0.8 && post_high_order >= 20 {
                bail!(
                    "Verification Failed: High-order block reduction ({:.1}%) is less than 80% \
                     and remaining blocks ({}) are not below absolute threshold (20). \
                     Memory fragmentation is insufficient.",
                    reduction * 100.0,
                    post_high_order
                );
            }
        }
        println!(
            "Success: Memory fragmentation successfully verified (relative reduction or absolute limit met)."
        );

        Some(frag)
    } else {
        None
    };

    for run in 1..=iterations {
        println!("--- Run {}/{} ---", run, iterations);
        let allocated_bytes = run_once(chunk_size_mib)
            .with_context(|| format!("Failed in run {}/{}", run, iterations))?;

        println!("Successfully allocated {} bytes", allocated_bytes);

        if let Ok(out_dir) = std::env::var("OUT_DIR") {
            write_metric(&out_dir, run, allocated_bytes)?;
            println!("Metric written to OUT_DIR");
        } else {
            println!("Warning: OUT_DIR not set, metric not saved to file.");
        }
    }

    // Write summary once after all iterations complete successfully!
    if let Ok(out_dir) = std::env::var("OUT_DIR") {
        write_summary(&out_dir, antagonize, iterations, chunk_size_mib)?;
        println!("Summary written to OUT_DIR");
    }

    if antagonize {
        println!("--- Releasing Memory Antagonist (Restoring RAM) ---");
        drop(_fragmenter);
    }

    println!("All {} runs completed successfully.", iterations);
    Ok(())
}

fn main() -> Result<()> {
    let mut size_mib = 2;
    let mut is_worker = false;
    let mut iterations = 1;
    let mut antagonize = false;

    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--size-mib" => {
                if i + 1 < args.len() {
                    size_mib = args[i + 1].parse::<usize>().context("Invalid size-mib")?;
                    i += 2;
                } else {
                    i += 1;
                }
            }
            "--worker" => {
                is_worker = true;
                i += 1;
            }
            // TODO: This flag is dumb, we should not have iterations inside the
            // benchmark here unless we have a way to communicate back out to
            // falba about restarts of the benchmark.
            "--iterations" => {
                if i + 1 < args.len() {
                    iterations = args[i + 1].parse::<usize>().context("Invalid iterations")?;
                    i += 2;
                } else {
                    i += 1;
                }
            }
            "--antagonize" => {
                antagonize = true;
                i += 1;
            }
            _ => i += 1,
        }
    }

    if is_worker {
        worker(size_mib)?;
    } else {
        runner(size_mib, iterations, antagonize)?;
    }

    Ok(())
}
