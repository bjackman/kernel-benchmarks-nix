use std::ptr;

fn main() {
    let mut size_mib = 32;
    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--size-mib" && i + 1 < args.len() {
            size_mib = args[i + 1].parse::<usize>().expect("Invalid size-mib");
            i += 2;
        } else {
            i += 1;
        }
    }

    let size = size_mib * 1024 * 1024;
    println!("Attempting to allocate {} MiB of secretmem", size_mib);

    // libc::SYS_memfd_secret is 447 on x86_64
    #[cfg(target_arch = "x86_64")]
    const SYS_MEMFD_SECRET: libc::c_long = 447;

    let fd = unsafe { libc::syscall(SYS_MEMFD_SECRET, 0) };
    if fd < 0 {
        panic!("memfd_secret failed: {}", std::io::Error::last_os_error());
    }

    if unsafe { libc::ftruncate(fd as i32, size as libc::off_t) } < 0 {
        panic!("ftruncate failed: {}", std::io::Error::last_os_error());
    }

    let addr = unsafe {
        libc::mmap(
            ptr::null_mut(),
            size,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_SHARED | libc::MAP_POPULATE,
            fd as i32,
            0,
        )
    };

    if addr == libc::MAP_FAILED {
        panic!("mmap failed: {}", std::io::Error::last_os_error());
    }

    println!("Successfully allocated {} MiB of secretmem", size_mib);
}
