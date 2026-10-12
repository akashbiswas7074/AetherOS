//! Lock-Free Zero-Copy Ring Buffer IPC for AetherOS Microkernel.
//! Enables microsecond-level message passing between isolated drivers and services.

use casfs::blake3::Blake3Hash;
use core::sync::atomic::{AtomicUsize, Ordering};

pub const RING_CAPACITY: usize = 32;

#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct KernelMessage {
    pub sender_id: u32,
    pub recipient_id: u32,
    pub opcode: u32,
    pub payload_hash: Blake3Hash,
    pub timestamp: u64,
}

impl KernelMessage {
    pub const EMPTY: Self = Self {
        sender_id: 0,
        recipient_id: 0,
        opcode: 0,
        payload_hash: Blake3Hash::ZERO,
        timestamp: 0,
    };
}

pub struct IpcRingBuffer {
    buffer: [KernelMessage; RING_CAPACITY],
    head: AtomicUsize,
    tail: AtomicUsize,
}

impl IpcRingBuffer {
    pub const fn new() -> Self {
        Self {
            buffer: [KernelMessage::EMPTY; RING_CAPACITY],
            head: AtomicUsize::new(0),
            tail: AtomicUsize::new(0),
        }
    }

    /// Pushes a message into the ring buffer (Lock-free)
    pub fn push(&mut self, msg: KernelMessage) -> bool {
        let current_tail = self.tail.load(Ordering::Acquire);
        let current_head = self.head.load(Ordering::Relaxed);

        if (current_tail + 1) % RING_CAPACITY == current_head {
            return false; // Ring buffer full
        }

        self.buffer[current_tail] = msg;
        self.tail.store((current_tail + 1) % RING_CAPACITY, Ordering::Release);
        true
    }

    /// Pops a message from the ring buffer (Lock-free)
    pub fn pop(&mut self) -> Option<KernelMessage> {
        let current_head = self.head.load(Ordering::Acquire);
        let current_tail = self.tail.load(Ordering::Relaxed);

        if current_head == current_tail {
            return None; // Ring buffer empty
        }

        let msg = self.buffer[current_head];
        self.head.store((current_head + 1) % RING_CAPACITY, Ordering::Release);
        Some(msg)
    }
}
