//! Cryptographic Zero-Trust Capability Tokens.
//! Replaces monolithic Unix 'root' and Windows 'Administrator' permissions.
//! Grants granular, unforgeable, time-bounded capabilities verified by cryptographic MACs.

use casfs::blake3::{hash, Blake3Hash};

pub mod permissions {
    pub const READ_STORAGE: u32 = 1 << 0;
    pub const WRITE_STORAGE: u32 = 1 << 1;
    pub const NETWORK_CONNECT: u32 = 1 << 2;
    pub const NETWORK_BIND: u32 = 1 << 3;
    pub const DISPLAY_SURFACE: u32 = 1 << 4;
    pub const DIRECT_MEM_DMA: u32 = 1 << 5;
    pub const EXEC_PROCESS: u32 = 1 << 6;
}

/// An unforgeable capability token presented by an application or user session
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CapabilityToken {
    pub token_id: u64,
    pub subject: &'static str,
    pub permissions_mask: u32,
    pub valid_until_tick: u64,
    pub signature: Blake3Hash,
}

impl CapabilityToken {
    /// Computes the cryptographic signature for a token using the OS Master Authority Key
    pub fn compute_signature(
        master_secret: &[u8; 32],
        token_id: u64,
        subject: &'static str,
        permissions_mask: u32,
        valid_until_tick: u64,
    ) -> Blake3Hash {
        let mut buffer = [0u8; 80];
        buffer[0..32].copy_from_slice(master_secret);
        buffer[32..40].copy_from_slice(&token_id.to_le_bytes());
        buffer[40..44].copy_from_slice(&permissions_mask.to_le_bytes());
        buffer[44..52].copy_from_slice(&valid_until_tick.to_le_bytes());

        let subject_bytes = subject.as_bytes();
        let copy_len = if subject_bytes.len() > 28 {
            28
        } else {
            subject_bytes.len()
        };
        buffer[52..52 + copy_len].copy_from_slice(&subject_bytes[..copy_len]);

        hash(&buffer)
    }

    /// Issues a new signed capability token
    pub fn issue(
        master_secret: &[u8; 32],
        token_id: u64,
        subject: &'static str,
        permissions_mask: u32,
        valid_until_tick: u64,
    ) -> Self {
        let signature = Self::compute_signature(
            master_secret,
            token_id,
            subject,
            permissions_mask,
            valid_until_tick,
        );

        Self {
            token_id,
            subject,
            permissions_mask,
            valid_until_tick,
            signature,
        }
    }

    /// Verifies authenticity and validates whether the token has specific permission
    pub fn verify_and_check_permission(
        &self,
        master_secret: &[u8; 32],
        required_permission: u32,
        current_tick: u64,
    ) -> bool {
        // 1. Check expiration
        if current_tick > self.valid_until_tick {
            return false;
        }

        // 2. Check permission flag
        if (self.permissions_mask & required_permission) != required_permission {
            return false;
        }

        // 3. Cryptographic signature check
        let expected_signature = Self::compute_signature(
            master_secret,
            self.token_id,
            self.subject,
            self.permissions_mask,
            self.valid_until_tick,
        );

        self.signature == expected_signature
    }
}
