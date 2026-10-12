//! 4KB Physical Frame Allocator for AetherOS Microkernel.

pub const PAGE_SIZE: usize = 4096;

pub struct PhysicalFrameAllocator {
    next_free_frame: usize,
    memory_limit: usize,
    allocated_count: usize,
}

impl PhysicalFrameAllocator {
    pub const fn new(start_addr: usize, memory_limit: usize) -> Self {
        Self {
            next_free_frame: start_addr,
            memory_limit,
            allocated_count: 0,
        }
    }

    /// Allocates a contiguous 4KB physical frame
    pub fn allocate_frame(&mut self) -> Option<usize> {
        if self.next_free_frame + PAGE_SIZE <= self.memory_limit {
            let addr = self.next_free_frame;
            self.next_free_frame += PAGE_SIZE;
            self.allocated_count += 1;
            Some(addr)
        } else {
            None
        }
    }

    pub fn allocated_frames(&self) -> usize {
        self.allocated_count
    }

    pub fn free_memory_bytes(&self) -> usize {
        if self.next_free_frame < self.memory_limit {
            self.memory_limit - self.next_free_frame
        } else {
            0
        }
    }
}
