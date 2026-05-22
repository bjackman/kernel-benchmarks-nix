#[cfg(not(target_os = "linux"))]
compile_error!("This benchmark only supports Linux.");

use anyhow::{Context, Result, anyhow, bail};
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

fn runner(chunk_size_mib: usize) -> Result<()> {
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

    for line in reader.lines() {
        let l = line.context("Failed to read line from worker stdout")?;
        if let Ok(bytes) = l.trim().parse::<u64>() {
            last_allocated_bytes = bytes;
            println!("Progress: {} MiB", last_allocated_bytes / (1024 * 1024));
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
            return Ok(());
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

fn main() -> Result<()> {
    let mut size_mib = 128;
    let mut is_worker = false;

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
            _ => i += 1,
        }
    }

    if is_worker {
        worker(size_mib)?;
    } else {
        runner(size_mib)?;
    }

    Ok(())
}
