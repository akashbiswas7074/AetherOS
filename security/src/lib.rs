//! AetherOS Blockchain-Grade Security Subsystem.
//!
//! Features:
//! 1. Immutable Audit Ledger (Blockchain Hash-Chain with Merkle Roots)
//! 2. Anti-Supply-Chain Attestation & Measured Boot Verification
//! 3. Cryptographic Zero-Trust Capability Tokens

#![no_std]

pub mod attestation;
pub mod ledger;
pub mod token;

pub use attestation::{
    AttestationStage, MeasuredBootChain, PackageAttestationRegistry, VerificationResult,
    VerifiedPackageEntry,
};
pub use ledger::{
    AuditBlock, AuditEvent, AuditEventKind, AuditLedger, MAX_BLOCKS_IN_LEDGER,
    MAX_EVENTS_PER_BLOCK,
};
pub use token::{permissions, CapabilityToken};

#[cfg(test)]
mod tests {
    use super::*;
    use casfs::blake3::hash;

    #[test]
    fn test_blockchain_audit_ledger_integrity() {
        let mut ledger = AuditLedger::new();

        // 1. Record boot event
        let ev1 = AuditEvent::new(
            AuditEventKind::BootAttestation,
            "kernel",
            hash(b"measured_kernel_elf64"),
            100,
        );
        ledger.record_event(ev1);

        // 2. Record package verified event
        let ev2 = AuditEvent::new(
            AuditEventKind::PackageVerified,
            "apk",
            hash(b"nano-8.0-official"),
            105,
        );
        ledger.record_event(ev2);

        // Commit block into blockchain
        let block0_hash = ledger.commit_current_block();
        assert_ne!(block0_hash, casfs::blake3::Blake3Hash::ZERO);
        assert_eq!(ledger.block_count, 1);

        // Verify valid chain
        assert!(ledger.verify_integrity());

        // 3. Add second block
        let ev3 = AuditEvent::new(
            AuditEventKind::CapabilityGranted,
            "auth_service",
            hash(b"user_akash_token"),
            200,
        );
        ledger.record_event(ev3);
        let block1_hash = ledger.commit_current_block();
        assert_ne!(block1_hash, block0_hash);
        assert_eq!(ledger.block_count, 2);

        // Chain must still be 100% valid
        assert!(ledger.verify_integrity());

        // 4. Simulate malicious tampering of block 0
        if let Some(ref mut tampered_block) = ledger.blocks[0] {
            tampered_block.index = 999; // Tamper with block index
        }

        // Integrity verification MUST fail!
        assert!(!ledger.verify_integrity());
    }

    #[test]
    fn test_anti_supply_chain_verification() {
        let mut registry = PackageAttestationRegistry::new();

        let genuine_nano = b"official_gnu_nano_8.0_binary_bytes_compiled";
        let genuine_hash = hash(genuine_nano);

        // Register on cryptographic consensus registry
        registry.register_package("nano", "8.0", genuine_hash, 1);

        // 1. Verify authentic binary
        assert_eq!(
            registry.verify_binary("nano", genuine_nano),
            VerificationResult::VerifiedAuthentic
        );

        // 2. Verify tampered binary (supply-chain backdoor attempt)
        let backdoored_nano = b"official_gnu_nano_8.0_binary_bytes_with_backdoor_payload";
        assert_eq!(
            registry.verify_binary("nano", backdoored_nano),
            VerificationResult::ChecksumMismatch
        );

        // 3. Unknown package
        assert_eq!(
            registry.verify_binary("unknown_pkg", b"data"),
            VerificationResult::PackageNotFound
        );
    }

    #[test]
    fn test_zero_trust_capability_token() {
        let master_key = [0x42u8; 32];
        let token = CapabilityToken::issue(
            &master_key,
            1001,
            "session_akash",
            permissions::READ_STORAGE | permissions::DISPLAY_SURFACE,
            5000,
        );

        // 1. Valid permission check at tick 1000
        assert!(token.verify_and_check_permission(
            &master_key,
            permissions::READ_STORAGE,
            1000
        ));
        assert!(token.verify_and_check_permission(
            &master_key,
            permissions::DISPLAY_SURFACE,
            1000
        ));

        // 2. Denied unauthorized permission (Direct Memory DMA)
        assert!(!token.verify_and_check_permission(
            &master_key,
            permissions::DIRECT_MEM_DMA,
            1000
        ));

        // 3. Denied expired token (tick 6000 > valid_until 5000)
        assert!(!token.verify_and_check_permission(
            &master_key,
            permissions::READ_STORAGE,
            6000
        ));

        // 4. Denied forged signature (wrong master key)
        let fake_key = [0x99u8; 32];
        assert!(!token.verify_and_check_permission(
            &fake_key,
            permissions::READ_STORAGE,
            1000
        ));
    }

    #[test]
    fn test_measured_boot_chain() {
        let mut boot_chain = MeasuredBootChain::new();

        let mbr_code = b"x86_stage1_boot_sector";
        let kernel_elf = b"aetheros_elf64_microkernel_binary";
        let driver_manifest = b"drivers_serial_vga_casfs_manifest";

        let pcr_mbr = boot_chain.extend_measurement(AttestationStage::MbrStage1, mbr_code);
        let pcr_kernel = boot_chain.extend_measurement(AttestationStage::KernelBareMetal, kernel_elf);
        let pcr_drivers = boot_chain.extend_measurement(AttestationStage::DriverManifest, driver_manifest);

        assert_eq!(boot_chain.measurements_count, 3);
        assert_ne!(pcr_mbr, pcr_kernel);
        assert_ne!(pcr_kernel, pcr_drivers);

        assert!(boot_chain.verify_state(pcr_drivers));
        assert!(!boot_chain.verify_state(pcr_kernel));
    }

    #[test]
    fn test_blockchain_secured_filesystem() {
        let mut ledger = AuditLedger::new();

        // 1. Commit file into filesystem and log to blockchain
        let file_data = b"system_critical_config=ananta_secure_v1";
        let file_hash = hash(file_data);

        let file_event = AuditEvent::new(
            AuditEventKind::FileCommitted,
            "casfs_engine",
            file_hash,
            500,
        );
        ledger.record_event(file_event);

        // 2. Switch system generation and log to blockchain
        let gen_event = AuditEvent::new(
            AuditEventKind::GenerationSwitched,
            "flake_manager",
            hash(b"generation_2_manifest_root"),
            510,
        );
        ledger.record_event(gen_event);

        // 3. Seal block and verify tamper-evidence
        let sealed_hash = ledger.commit_current_block();
        assert_ne!(sealed_hash, casfs::blake3::Blake3Hash::ZERO);
        assert!(ledger.verify_integrity());
        assert_eq!(ledger.block_count, 1);
    }

    #[test]
    fn test_folder_and_file_creation_blockchain_security() {
        let mut ledger = AuditLedger::new();

        // 1. Every folder creation is secured by blockchain
        let folder_event = AuditEvent::new(
            AuditEventKind::DirectoryCreated,
            "casfs_watch_daemon",
            hash(b"/home/ananta/workspace"),
            600,
        );
        ledger.record_event(folder_event);

        // 2. Every file created inside the folder is secured by blockchain
        let file_event = AuditEvent::new(
            AuditEventKind::FileCreated,
            "casfs_watch_daemon",
            hash(b"hello_world.c_source_code_payload"),
            601,
        );
        ledger.record_event(file_event);

        // 3. Block seals and ledger verifies tamper-evidence
        let sealed_block_hash = ledger.commit_current_block();
        assert_ne!(sealed_block_hash, casfs::blake3::Blake3Hash::ZERO);
        assert!(ledger.verify_integrity());
        assert_eq!(ledger.current_block.index, 1);
    }
}
