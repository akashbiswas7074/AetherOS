//! Bounded $O(1)$ Hash Array Mapped Trie (HAMT) for ultra-fast object lookup.
//! Zero directory traversal latency; maps 256-bit BLAKE3 hash -> Physical Extent.

use crate::blake3::Blake3Hash;

pub const HAMT_WIDTH: usize = 32; // 5 bits per trie level

/// Physical storage extent description (LBA block address + count)
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct PhysicalExtent {
    pub block_offset: u64,
    pub block_count: u32,
    pub byte_length: u64,
    pub flags: u32,
}

/// An entry in the CasFS index
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CasObjectEntry {
    pub hash: Blake3Hash,
    pub extent: PhysicalExtent,
    pub generation: u64,
}

/// A compact fixed-capacity Trie node for bare-metal `#![no_std]` execution
pub struct CasTrieNode {
    pub mask: u32,
    pub entries: [Option<CasObjectEntry>; HAMT_WIDTH],
}

impl CasTrieNode {
    pub const fn new() -> Self {
        const NONE_ENTRY: Option<CasObjectEntry> = None;
        Self {
            mask: 0,
            entries: [NONE_ENTRY; HAMT_WIDTH],
        }
    }

    #[inline]
    pub fn insert(&mut self, entry: CasObjectEntry, depth: usize) -> bool {
        if depth >= 32 {
            return false;
        }
        // Extract 5-bit index from the hash
        let byte_pos = (depth * 5) / 8;
        let bit_offset = (depth * 5) % 8;
        let hash_bytes = entry.hash.as_bytes();

        let val = if byte_pos + 1 < hash_bytes.len() {
            let combined = ((hash_bytes[byte_pos] as u16) | ((hash_bytes[byte_pos + 1] as u16) << 8)) >> bit_offset;
            (combined & 0x1F) as usize
        } else {
            ((hash_bytes[byte_pos] >> bit_offset) & 0x1F) as usize
        };

        self.mask |= 1 << val;
        self.entries[val] = Some(entry);
        true
    }

    #[inline]
    pub fn lookup(&self, hash: &Blake3Hash, depth: usize) -> Option<PhysicalExtent> {
        if depth >= 32 {
            return None;
        }
        let byte_pos = (depth * 5) / 8;
        let bit_offset = (depth * 5) % 8;
        let hash_bytes = hash.as_bytes();

        let val = if byte_pos + 1 < hash_bytes.len() {
            let combined = ((hash_bytes[byte_pos] as u16) | ((hash_bytes[byte_pos + 1] as u16) << 8)) >> bit_offset;
            (combined & 0x1F) as usize
        } else {
            ((hash_bytes[byte_pos] >> bit_offset) & 0x1F) as usize
        };

        if (self.mask & (1 << val)) != 0 {
            if let Some(ref entry) = self.entries[val] {
                if &entry.hash == hash {
                    return Some(entry.extent);
                }
            }
        }
        None
    }
}
