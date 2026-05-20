use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::ptr;

// libc::SYS_memfd_secret is 447 on x86_64
#[cfg(target_arch = "x86_64")]
const SYS_MEMFD_SECRET: libc::c_long = 447;

fn worker(chunk_size_mib: usize) {
    // Set OOM score to 1000 to be first in line for OOM killer.
    if let Ok(mut f) = std::fs::File::create("/proc/self/oom_score_adj") {
        let _ = f.write_all(b"1000");
    }

    // Try to increase the FD limit to the maximum allowed.
    let mut rlim = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    if unsafe { libc::getrlimit(libc::RLIMIT_NOFILE, &mut rlim) } == 0 {
        rlim.rlim_cur = rlim.rlim_max;
        unsafe {
            libc::setrlimit(libc::RLIMIT_NOFILE, &rlim);
        }
    }

    let chunk_size = chunk_size_mib * 1024 * 1024;
    let mut total_allocated: u64 = 0;
    let mut chunks = Vec::new();

    loop {
        let fd = unsafe { libc::syscall(SYS_MEMFD_SECRET, 0) };
        if fd < 0 {
            panic!(
                "memfd_secret failed after {} MiB: {}",
                total_allocated / (1024 * 1024),
                std::io::Error::last_os_error()
            );
        }

        if unsafe { libc::ftruncate(fd as i32, chunk_size as libc::off_t) } < 0 {
            panic!(
                "ftruncate failed after {} MiB: {}",
                total_allocated / (1024 * 1024),
                std::io::Error::last_os_error()
            );
        }

        let addr = unsafe {
            libc::mmap(
                ptr::null_mut(),
                chunk_size,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED | libc::MAP_POPULATE,
                fd as i32,
                0,
            )
        };

        if addr == libc::MAP_FAILED {
            panic!(
                "mmap failed after {} MiB: {}",
                total_allocated / (1024 * 1024),
                std::io::Error::last_os_error()
            );
        }

        // Explicitly write to each page to ensure it's backed by physical memory.
        // Use multiple threads to speed this up, similar to page_alloc_bench.
        let num_threads = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(1);
        let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) as usize };
        let chunk_ptr = addr as usize;

        std::thread::scope(|s| {
            let chunk_per_thread = chunk_size / num_threads;
            for t in 0..num_threads {
                let start_offset = t * chunk_per_thread;
                let end_offset = if t == num_threads - 1 {
                    chunk_size
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

        total_allocated += chunk_size as u64;
        chunks.push((fd, addr));
        println!("{}", total_allocated);
        let _ = std::io::stdout().flush();
    }
}

fn runner(chunk_size_mib: usize) {
    let mut child = Command::new(std::env::current_exe().unwrap())
        .arg("--worker")
        .arg("--size-mib")
        .arg(chunk_size_mib.to_string())
        .stdout(Stdio::piped())
        .spawn()
        .expect("Failed to spawn worker");

    let stdout = child.stdout.take().expect("Failed to open worker stdout");
    let reader = BufReader::new(stdout);
    let mut last_allocated_bytes: u64 = 0;

    for line in reader.lines() {
        if let Ok(l) = line {
            if let Ok(bytes) = l.trim().parse::<u64>() {
                last_allocated_bytes = bytes;
                println!("Progress: {} MiB", last_allocated_bytes / (1024 * 1024));
            }
        }
    }

    let status = child.wait().expect("Failed to wait for worker");

    #[cfg(target_family = "unix")]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(signal) = status.signal() {
            println!(
                "Worker killed by signal {} after allocating {} MiB",
                signal,
                last_allocated_bytes / (1024 * 1024)
            );
            if signal == 9 {
                println!("Likely OOM killed.");
                std::process::exit(0);
            } else {
                eprintln!("Worker killed by unexpected signal: {}", signal);
                std::process::exit(1);
            }
        } else {
            let code = status.code().unwrap_or(-1);
            eprintln!(
                "Worker failed with status {} after allocating {} MiB",
                code,
                last_allocated_bytes / (1024 * 1024)
            );
            std::process::exit(1);
        }
    }
}

fn main() {
    let mut size_mib = 1024;
    let mut is_worker = false;

    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--size-mib" => {
                if i + 1 < args.len() {
                    size_mib = args[i + 1].parse::<usize>().expect("Invalid size-mib");
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
        worker(size_mib);
    } else {
        runner(size_mib);
    }
}
