use anyhow::{Context, Result, bail};
use nix::sys::mman::{MapFlags, ProtFlags, mmap_anonymous, munmap};
use nix::unistd::{SysconfVar, sysconf};
use std::ffi::c_void;
use std::num::NonZeroUsize;
use std::ptr::{self, NonNull};

/// Represents a single allocated physical memory block.
/// When dropped, it automatically unmaps the memory, freeing it back to the OS.
struct FragmentBlock {
    addr: NonNull<c_void>,
    size: usize,
}

impl FragmentBlock {
    fn new(size: usize) -> Result<Self> {
        let size_nz = NonZeroUsize::new(size).context("block size must be non-zero")?;

        // We map anonymously.
        // This ensures the pages are allocated from the kernel's "Movable" pageblocks.
        let flags = MapFlags::MAP_PRIVATE | MapFlags::MAP_ANONYMOUS;
        let prot = ProtFlags::PROT_READ | ProtFlags::PROT_WRITE;

        let addr = unsafe { mmap_anonymous(None, size_nz, prot, flags) }
            .context("mmap_anonymous failed for fragmentation allocation")?;

        let block = FragmentBlock { addr, size };

        // Populate every single page inside the block to force physical allocation
        // inside the Movable pageblocks.
        block.populate()?;

        Ok(block)
    }

    fn populate(&self) -> Result<()> {
        let page_size = sysconf(SysconfVar::PAGE_SIZE)
            .context("Failed to get page size via sysconf")?
            .context("PAGE_SIZE is not supported by this system")? as usize;

        let ptr = self.addr.as_ptr() as usize;

        // Write volatile data to every single page.
        // We write the actual virtual address of each page into itself.
        // This ensures the page cannot be deduplicated by KSM.
        // Safe because we are writing inside our allocated memory bounds.
        for offset in (0..self.size).step_by(page_size) {
            unsafe {
                ptr::write_volatile((ptr + offset) as *mut usize, ptr + offset);
            }
        }
        Ok(())
    }
}

impl Drop for FragmentBlock {
    fn drop(&mut self) {
        // Safe because the memory was allocated by this struct and we own it.
        unsafe {
            if let Err(e) = munmap(self.addr, self.size) {
                eprintln!(
                    "Warning: Failed to munmap fragment block at {:?}: {}",
                    self.addr, e
                );
            }
        }
    }
}

pub struct MemoryFragmenter {
    _fragment_blocks: Vec<FragmentBlock>,
}

impl MemoryFragmenter {
    pub fn antagonize(target_free_ratio: f64) -> Result<Self> {
        // Read baseline meminfo
        let mem_free_kb =
            read_free_memory_kb().context("Failed to read free memory for fragmenter")?;
        let mem_free_bytes = mem_free_kb * 1024;

        // Target memory to lock is target_free_ratio of free memory.
        let target_lock_bytes = (mem_free_bytes as f64 * target_free_ratio) as usize;

        // We use 64KB chunks.
        // Statistically, randomly scattering unmovable 64KB blocks across memory
        // guarantees that the probability of finding a contiguous 2MB free block
        // is virtually zero, achieving absolute fragmentation for huge pages.
        let block_size = 64 * 1024;
        let num_target_blocks = target_lock_bytes / block_size;

        println!(
            "Fragmenter: Free memory: {} MiB, targeting {} MiB ({:.0}% of free) in {} x {}KB blocks",
            mem_free_bytes / (1024 * 1024),
            target_lock_bytes / (1024 * 1024),
            target_free_ratio * 100.0,
            num_target_blocks,
            block_size / 1024
        );

        let mut fragment_blocks = Vec::with_capacity(num_target_blocks);

        // Phase 1: Allocate contiguous blocks (pollute Movable pageblocks)
        for i in 0..num_target_blocks {
            match FragmentBlock::new(block_size) {
                Ok(block) => fragment_blocks.push(block),
                Err(e) => {
                    println!(
                        "Warning: Allocation failed at block {}/{}: {}. Halting allocation phase.",
                        i, num_target_blocks, e
                    );
                    break;
                }
            }
        }

        let actual_allocated = fragment_blocks.len();
        println!(
            "Fragmenter: Allocated {} MiB ({} blocks)",
            (actual_allocated * block_size) / (1024 * 1024),
            actual_allocated
        );

        if actual_allocated < 2 {
            bail!(
                "Fragmenter: Not enough memory was allocated to perform fragmentation (need at least 2 blocks)."
            );
        }

        // Phase 2: Unmap every second block to create the "Swiss Cheese" pattern
        // We drop every second block from the vector, which triggers its Drop implementation.
        let mut active_fragments = Vec::with_capacity(actual_allocated / 2 + 1);
        for (i, block) in fragment_blocks.into_iter().enumerate() {
            if i % 2 == 0 {
                // Keep this block allocated
                active_fragments.push(block);
            } else {
                // Drop this block (implicitly calls munmap via Drop)
                // This creates a free hole.
            }
        }

        let final_fragments = active_fragments.len();
        println!(
            "Fragmenter: Fragmentation complete. Created {} x {}KB free holes separated by {} x {}KB allocated blocks.",
            actual_allocated - final_fragments,
            block_size / 1024,
            final_fragments,
            block_size / 1024
        );

        Ok(MemoryFragmenter {
            _fragment_blocks: active_fragments,
        })
    }
}

fn read_free_memory_kb() -> Result<u64> {
    let content =
        std::fs::read_to_string("/proc/meminfo").context("Failed to read /proc/meminfo")?;
    for line in content.lines() {
        if line.starts_with("MemFree:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                let kb = parts[1]
                    .parse::<u64>()
                    .context("Failed to parse MemFree value")?;
                return Ok(kb);
            }
        }
    }
    bail!("Could not find MemFree in /proc/meminfo");
}

pub fn count_high_order_free_blocks() -> Result<u64> {
    let buddyinfo =
        std::fs::read_to_string("/proc/buddyinfo").context("Failed to read /proc/buddyinfo")?;
    let mut count = 0;

    for line in buddyinfo.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 4 {
            let zone = parts[3];
            if zone == "DMA32" || zone == "Normal" {
                if parts.len() >= 15 {
                    let order9 = parts[13]
                        .parse::<u64>()
                        .context("Failed to parse order 9 count")?;
                    let order10 = parts[14]
                        .parse::<u64>()
                        .context("Failed to parse order 10 count")?;
                    count += order9 + order10;
                }
            }
        }
    }
    Ok(count)
}

pub fn print_buddyinfo_summary() -> Result<()> {
    let buddyinfo =
        std::fs::read_to_string("/proc/buddyinfo").context("Failed to read /proc/buddyinfo")?;
    for line in buddyinfo.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 4 {
            let zone = parts[3];
            if zone == "DMA32" || zone == "Normal" {
                if parts.len() >= 15 {
                    println!(
                        "Zone {} - Order 8 (1MB): {}, Order 9 (2MB): {}, Order 10 (4MB): {}",
                        zone, parts[12], parts[13], parts[14]
                    );
                }
            }
        }
    }
    Ok(())
}
