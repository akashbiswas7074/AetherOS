//! Hardware & Software Attestation and Anti-Supply-Chain Verification.
//! Protects against compromised mirrors, backdoored binaries, and bootkit modifications.

use casfs::blake3::{hash, Blake3Hash};

pub const MAX_VERIFIED_PACKAGES: usize = 16;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AttestationStage {
    MbrStage1,
    KernelBareMetal,
    DriverManifest,
    UserspaceInit,
}

/// Cumulative Measured Boot Attestation Register (TPM/PCR-style chain)
#[derive(Clone, Copy, Debug)]
pub struct MeasuredBootChain {
    pub pcr_cumulative: Blake3Hash,
    pub measurements_count: usize,
}

impl MeasuredBootChain {
    pub const fn new() -> Self {
        Self {
            pcr_cumulative: Blake3Hash::ZERO,
            measurements_count: 0,
        }
    }

    /// Extends the cumulative cryptographic PCR hash:
    /// PCR_new = BLAKE3(PCR_prev || BLAKE3(stage_bytes))
    pub fn extend_measurement(&mut self, stage: AttestationStage, data: &[u8]) -> Blake3Hash {
        let stage_hash = hash(data);
        let mut buffer = [0u8; 65];
        buffer[0] = stage as u8;
        buffer[1..33].copy_from_slice(self.pcr_cumulative.as_bytes());
        buffer[33..65].copy_from_slice(stage_hash.as_bytes());

        self.pcr_cumulative = hash(&buffer);
        self.measurements_count += 1;
        self.pcr_cumulative
    }

    /// Validates whether the runtime measured state matches the expected reference hash
    pub fn verify_state(&self, reference_hash: Blake3Hash) -> bool {
        self.pcr_cumulative == reference_hash
    }
}

/// Package entry registered on the cryptographic consensus registry
#[derive(Clone, Copy, Debug)]
pub struct VerifiedPackageEntry {
    pub package_name: &'static str,
    pub version: &'static str,
    pub expected_hash: Blake3Hash,
    pub required_abi_version: u16,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VerificationResult {
    VerifiedAuthentic,
    ChecksumMismatch,
    PackageNotFound,
}

/// Decentralized Package Registry for supply-chain attack prevention
pub struct PackageAttestationRegistry {
    pub entry_count: usize,
    pub entries: [Option<VerifiedPackageEntry>; MAX_VERIFIED_PACKAGES],
}

impl PackageAttestationRegistry {
    pub const fn new() -> Self {
        const NONE_ENTRY: Option<VerifiedPackageEntry> = None;
        Self {
            entry_count: 0,
            entries: [NONE_ENTRY; MAX_VERIFIED_PACKAGES],
        }
    }

    /// Registers a certified upstream package hash
    pub fn register_package(
        &mut self,
        package_name: &'static str,
        version: &'static str,
        expected_hash: Blake3Hash,
        required_abi_version: u16,
    ) -> bool {
        if self.entry_count < MAX_VERIFIED_PACKAGES {
            self.entries[self.entry_count] = Some(VerifiedPackageEntry {
                package_name,
                version,
                expected_hash,
                required_abi_version,
            });
            self.entry_count += 1;
            true
        } else {
            false
        }
    }

    /// Verifies that a downloaded binary file matches the cryptographic consensus hash.
    /// Protects against compromised upstream mirrors or man-in-the-middle package tampering.
    pub fn verify_binary(&self, package_name: &str, binary_bytes: &[u8]) -> VerificationResult {
        for i in 0..self.entry_count {
            if let Some(ref entry) = self.entries[i] {
                if entry.package_name == package_name {
                    let actual_hash = hash(binary_bytes);
                    return if actual_hash == entry.expected_hash {
                        VerificationResult::VerifiedAuthentic
                    } else {
                        VerificationResult::ChecksumMismatch
                    };
                }
            }
        }
        VerificationResult::PackageNotFound
    }
}
