#![no_std]

pub mod blake3;
pub mod hamt;
pub mod storage;

pub use blake3::{hash, Blake3Hash};
pub use hamt::{CasObjectEntry, CasTrieNode, PhysicalExtent};
pub use storage::CasStorageEngine;

/// Directory entry for recursive blockchain folder Merkle tree verification
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MerkleDirEntry {
    pub name: [u8; 32],
    pub name_len: usize,
    pub content_hash: Blake3Hash,
    pub is_dir: bool,
}

impl MerkleDirEntry {
    pub fn new(name_str: &str, content_hash: Blake3Hash, is_dir: bool) -> Self {
        let mut name = [0u8; 32];
        let bytes = name_str.as_bytes();
        let len = bytes.len().min(32);
        name[..len].copy_from_slice(&bytes[..len]);
        Self {
            name,
            name_len: len,
            content_hash,
            is_dir,
        }
    }

    pub fn compute_entry_hash(&self) -> Blake3Hash {
        let mut buf = [0u8; 65];
        buf[0] = if self.is_dir { 1 } else { 0 };
        buf[1..33].copy_from_slice(self.content_hash.as_bytes());
        buf[33..33 + self.name_len].copy_from_slice(&self.name[..self.name_len]);
        hash(&buf[..33 + self.name_len])
    }
}

pub const MAX_DIR_ENTRIES: usize = 32;

/// A directory node represented as a cryptographic Merkle tree
#[derive(Clone, Copy, Debug)]
pub struct MerkleDirectory {
    pub entries: [Option<MerkleDirEntry>; MAX_DIR_ENTRIES],
    pub entry_count: usize,
}

impl MerkleDirectory {
    pub const fn new() -> Self {
        const NONE_ENTRY: Option<MerkleDirEntry> = None;
        Self {
            entries: [NONE_ENTRY; MAX_DIR_ENTRIES],
            entry_count: 0,
        }
    }

    pub fn add_entry(&mut self, entry: MerkleDirEntry) -> bool {
        if self.entry_count < MAX_DIR_ENTRIES {
            self.entries[self.entry_count] = Some(entry);
            self.entry_count += 1;
            true
        } else {
            false
        }
    }

    /// Computes the aggregate Merkle Root Hash of the entire folder
    pub fn compute_folder_hash(&self) -> Blake3Hash {
        if self.entry_count == 0 {
            return Blake3Hash::ZERO;
        }
        let mut buffer = [0u8; MAX_DIR_ENTRIES * 32];
        for i in 0..self.entry_count {
            if let Some(ref entry) = self.entries[i] {
                let h = entry.compute_entry_hash();
                buffer[i * 32..(i + 1) * 32].copy_from_slice(h.as_bytes());
            }
        }
        hash(&buffer[..self.entry_count * 32])
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_blake3_hashing() {
        let payload = b"AetherOS bare metal content-addressed kernel";
        let h1 = hash(payload);
        let h2 = hash(payload);
        assert_eq!(h1, h2);
        assert_ne!(h1, Blake3Hash::ZERO);
    }

    #[test]
    fn test_cas_deduplication() {
        let mut engine = CasStorageEngine::new();
        let payload = b"identical_driver_binary_payload";

        let (hash1, was_new1) = engine.store(payload, 1);
        assert!(was_new1);
        assert_eq!(engine.object_count, 1);

        let (hash2, was_new2) = engine.store(payload, 1);
        assert!(!was_new2); // Must be deduplicated!
        assert_eq!(hash1, hash2);
        assert_eq!(engine.object_count, 1); // No new object allocated
        assert_eq!(engine.deduplicated_bytes_saved, payload.len() as u64);
    }

    #[test]
    fn test_hamt_lookup() {
        let mut engine = CasStorageEngine::new();
        let data = b"hyper_fast_os_config_file";
        let (hash, _) = engine.store(data, 1);

        let extent = engine.lookup(&hash);
        assert!(extent.is_some());
        let extent = extent.unwrap();
        assert_eq!(extent.byte_length, data.len() as u64);
    }

    #[test]
    fn test_merkle_directory_folder_verification() {
        let mut dir = MerkleDirectory::new();
        let file1_hash = hash(b"kernel_config_v1");
        let file2_hash = hash(b"user_profile_data");

        let entry1 = MerkleDirEntry::new("config.nix", file1_hash, false);
        let entry2 = MerkleDirEntry::new("home.nix", file2_hash, false);

        assert!(dir.add_entry(entry1));
        assert!(dir.add_entry(entry2));

        let folder_hash = dir.compute_folder_hash();
        assert_ne!(folder_hash, Blake3Hash::ZERO);

        // Verification of tamper detection: if file content changes, folder Merkle root changes
        let mut tampered_dir = MerkleDirectory::new();
        let tampered_entry1 = MerkleDirEntry::new("config.nix", hash(b"tampered_evil_config"), false);
        tampered_dir.add_entry(tampered_entry1);
        tampered_dir.add_entry(entry2);

        let tampered_folder_hash = tampered_dir.compute_folder_hash();
        assert_ne!(folder_hash, tampered_folder_hash);
    }
}
