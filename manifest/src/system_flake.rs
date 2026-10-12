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
