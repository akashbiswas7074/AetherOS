#![no_std]

pub mod blake3;
pub mod hamt;
pub mod storage;

pub use blake3::{hash, Blake3Hash};
pub use hamt::{CasObjectEntry, CasTrieNode, PhysicalExtent};
pub use storage::CasStorageEngine;

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
}
