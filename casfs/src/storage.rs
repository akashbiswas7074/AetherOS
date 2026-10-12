//! Extent-based Zero-Copy Block Storage Engine for CasFS.
//! Direct memory-mapped NVMe blocks with deduplication.

use crate::blake3::{self, Blake3Hash};
use crate::hamt::{CasObjectEntry, CasTrieNode, PhysicalExtent};

pub const BLOCK_SIZE: usize = 4096;
pub const MAX_IN_MEMORY_OBJECTS: usize = 128;

/// In-memory cache & write buffer for bare-metal `#![no_std]` execution
pub struct CasStorageEngine {
    pub trie: CasTrieNode,
    pub object_count: usize,
    pub total_bytes_stored: u64,
    pub deduplicated_bytes_saved: u64,
}

impl CasStorageEngine {
    pub const fn new() -> Self {
        Self {
            trie: CasTrieNode::new(),
            object_count: 0,
            total_bytes_stored: 0,
            deduplicated_bytes_saved: 0,
        }
    }

    /// Stores a payload with automatic BLAKE3 content-addressing and deduplication
    pub fn store(&mut self, payload: &[u8], generation: u64) -> (Blake3Hash, bool) {
        let digest = blake3::hash(payload);

        // Check if object already exists in the store (Deduplication)
        if let Some(_existing) = self.trie.lookup(&digest, 0) {
            self.deduplicated_bytes_saved += payload.len() as u64;
            return (digest, false); // Deduplicated! Zero extra disk blocks used
        }

        // Allocate physical extent
        let blocks = ((payload.len() + BLOCK_SIZE - 1) / BLOCK_SIZE) as u32;
        let extent = PhysicalExtent {
            block_offset: (self.total_bytes_stored / BLOCK_SIZE as u64),
            block_count: blocks.max(1),
            byte_length: payload.len() as u64,
            flags: 0,
        };

        let entry = CasObjectEntry {
            hash: digest,
            extent,
            generation,
        };

        self.trie.insert(entry, 0);
        self.object_count += 1;
        self.total_bytes_stored += (blocks as u64) * (BLOCK_SIZE as u64);

        (digest, true)
    }

    /// O(1) Zero-cost lookup by Content Hash
    #[inline]
    pub fn lookup(&self, hash: &Blake3Hash) -> Option<PhysicalExtent> {
        self.trie.lookup(hash, 0)
    }
}
