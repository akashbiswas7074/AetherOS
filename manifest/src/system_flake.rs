//! Declarative System Flake Engine (Native NixOS-style Generation Management).
//! Every system state is an immutable Merkle root with instant Hot-Rollbacks.

use casfs::blake3::{hash, Blake3Hash};

pub const MAX_SYSTEM_DRIVERS: usize = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DriverKind {
    SerialConsole,
    FramebufferDisplay,
    NvmeBlockStorage,
    KeyboardInput,
    NetworkInterface,
}

#[derive(Clone, Copy, Debug)]
pub struct DriverManifest {
    pub name: &'static str,
    pub kind: DriverKind,
    pub binary_hash: Blake3Hash,
    pub memory_limit_pages: usize,
}

/// A System Generation Flake
#[derive(Clone, Copy, Debug)]
pub struct SystemFlake {
    pub generation_id: u64,
    pub root_hash: Blake3Hash,
    pub driver_count: usize,
    pub drivers: [Option<DriverManifest>; MAX_SYSTEM_DRIVERS],
}

impl SystemFlake {
    pub const fn new(generation_id: u64) -> Self {
        const NONE_DRIVER: Option<DriverManifest> = None;
        Self {
            generation_id,
            root_hash: Blake3Hash::ZERO,
            driver_count: 0,
            drivers: [NONE_DRIVER; MAX_SYSTEM_DRIVERS],
        }
    }

    pub fn add_driver(&mut self, driver: DriverManifest) -> bool {
        if self.driver_count < MAX_SYSTEM_DRIVERS {
            self.drivers[self.driver_count] = Some(driver);
            self.driver_count += 1;
            true
        } else {
            false
        }
    }

    /// Evaluates the Merkle Root of the entire operating system generation
    pub fn compute_generation_hash(&mut self) -> Blake3Hash {
        // Collect driver hash bytes
        let mut buffer = [0u8; 32 * MAX_SYSTEM_DRIVERS + 8];
        buffer[0..8].copy_from_slice(&self.generation_id.to_le_bytes());

        let mut offset = 8;
        for i in 0..self.driver_count {
            if let Some(drv) = self.drivers[i] {
                buffer[offset..offset + 32].copy_from_slice(drv.binary_hash.as_bytes());
                offset += 32;
            }
        }

        self.root_hash = hash(&buffer[..offset]);
        self.root_hash
    }
}

pub const MAX_GENERATIONS: usize = 16;

#[derive(Clone, Copy, Debug)]
pub struct GenerationRecord {
    pub id: u64,
    pub root_hash: Blake3Hash,
    pub timestamp_tick: u64,
    pub active: bool,
}

#[derive(Clone, Copy, Debug)]
pub struct GenerationManager {
    pub count: usize,
    pub active_index: usize,
    pub generations: [Option<GenerationRecord>; MAX_GENERATIONS],
}

impl GenerationManager {
    pub const fn new() -> Self {
        const NONE_REC: Option<GenerationRecord> = None;
        Self {
            count: 0,
            active_index: 0,
            generations: [NONE_REC; MAX_GENERATIONS],
        }
    }

    pub fn record_generation(
        &mut self,
        id: u64,
        root_hash: Blake3Hash,
        timestamp_tick: u64,
    ) -> bool {
        if self.count < MAX_GENERATIONS {
            for i in 0..self.count {
                if let Some(ref mut rec) = self.generations[i] {
                    rec.active = false;
                }
            }
            let rec = GenerationRecord {
                id,
                root_hash,
                timestamp_tick,
                active: true,
            };
            self.generations[self.count] = Some(rec);
            self.active_index = self.count;
            self.count += 1;
            true
        } else {
            false
        }
    }

    pub fn rollback(&mut self) -> Option<GenerationRecord> {
        if self.active_index > 0 {
            if let Some(ref mut cur) = self.generations[self.active_index] {
                cur.active = false;
            }
            self.active_index -= 1;
            if let Some(ref mut prev) = self.generations[self.active_index] {
                prev.active = true;
                return Some(*prev);
            }
        }
        None
    }

    pub fn switch_to(&mut self, target_id: u64) -> Option<GenerationRecord> {
        let mut target_idx = None;
        for i in 0..self.count {
            if let Some(ref rec) = self.generations[i] {
                if rec.id == target_id {
                    target_idx = Some(i);
                    break;
                }
            }
        }

        if let Some(idx) = target_idx {
            if let Some(ref mut cur) = self.generations[self.active_index] {
                cur.active = false;
            }
            self.active_index = idx;
            if let Some(ref mut target) = self.generations[idx] {
                target.active = true;
                return Some(*target);
            }
        }
        None
    }
}
