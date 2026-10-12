//! Cryptographic Immutable Audit Ledger (Blockchain Hash-Chain).
//! All system security events are hashed into append-only Merkle-linked blocks.
//! Prevents anti-forensics attacks: logs cannot be altered retroactively.

use casfs::blake3::{hash, Blake3Hash};

pub const MAX_EVENTS_PER_BLOCK: usize = 8;
pub const MAX_BLOCKS_IN_LEDGER: usize = 16;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AuditEventKind {
    BootAttestation,
    PackageVerified,
    CapabilityGranted,
    IntegrityAlert,
    SyscallDenied,
    FileCommitted,
    GenerationSwitched,
    DirectoryCreated,
    FileCreated,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AuditEvent {
    pub kind: AuditEventKind,
    pub actor: &'static str,
    pub payload_hash: Blake3Hash,
    pub timestamp_tick: u64,
}

impl AuditEvent {
    pub const fn new(
        kind: AuditEventKind,
        actor: &'static str,
        payload_hash: Blake3Hash,
        timestamp_tick: u64,
    ) -> Self {
        Self {
            kind,
            actor,
            payload_hash,
            timestamp_tick,
        }
    }

    /// Computes the unique BLAKE3 hash of this audit event
    pub fn compute_hash(&self) -> Blake3Hash {
        let mut buffer = [0u8; 64];
        buffer[0] = self.kind as u8;
        buffer[1..9].copy_from_slice(&self.timestamp_tick.to_le_bytes());
        buffer[9..41].copy_from_slice(self.payload_hash.as_bytes());
        let actor_bytes = self.actor.as_bytes();
        let copy_len = if actor_bytes.len() > 23 {
            23
        } else {
            actor_bytes.len()
        };
        buffer[41..41 + copy_len].copy_from_slice(&actor_bytes[..copy_len]);

        hash(&buffer)
    }
}

/// An individual immutable block in the system audit chain
#[derive(Clone, Copy, Debug)]
pub struct AuditBlock {
    pub index: u64,
    pub prev_block_hash: Blake3Hash,
    pub merkle_root: Blake3Hash,
    pub event_count: usize,
    pub events: [Option<AuditEvent>; MAX_EVENTS_PER_BLOCK],
    pub block_hash: Blake3Hash,
}

impl AuditBlock {
    pub const fn empty(index: u64, prev_block_hash: Blake3Hash) -> Self {
        const NONE_EVENT: Option<AuditEvent> = None;
        Self {
            index,
            prev_block_hash,
            merkle_root: Blake3Hash::ZERO,
            event_count: 0,
            events: [NONE_EVENT; MAX_EVENTS_PER_BLOCK],
            block_hash: Blake3Hash::ZERO,
        }
    }

    pub fn add_event(&mut self, event: AuditEvent) -> bool {
        if self.event_count < MAX_EVENTS_PER_BLOCK {
            self.events[self.event_count] = Some(event);
            self.event_count += 1;
            true
        } else {
            false
        }
    }

    /// Computes the Merkle Root of all events contained in the block
    pub fn compute_merkle_root(&mut self) -> Blake3Hash {
        if self.event_count == 0 {
            self.merkle_root = Blake3Hash::ZERO;
            return self.merkle_root;
        }

        let mut combined = [0u8; MAX_EVENTS_PER_BLOCK * 32];
        for i in 0..self.event_count {
            if let Some(ref ev) = self.events[i] {
                let h = ev.compute_hash();
                combined[i * 32..(i + 1) * 32].copy_from_slice(h.as_bytes());
            }
        }

        self.merkle_root = hash(&combined[0..self.event_count * 32]);
        self.merkle_root
    }

    /// Seals the block and calculates its final cryptographic header hash
    pub fn seal(&mut self) -> Blake3Hash {
        self.compute_merkle_root();

        let mut header = [0u8; 80];
        header[0..8].copy_from_slice(&self.index.to_le_bytes());
        header[8..40].copy_from_slice(self.prev_block_hash.as_bytes());
        header[40..72].copy_from_slice(self.merkle_root.as_bytes());
        header[72..80].copy_from_slice(&(self.event_count as u64).to_le_bytes());

        self.block_hash = hash(&header);
        self.block_hash
    }
}

/// The system-wide blockchain audit ledger
pub struct AuditLedger {
    pub block_count: usize,
    pub blocks: [Option<AuditBlock>; MAX_BLOCKS_IN_LEDGER],
    pub current_block: AuditBlock,
}

impl AuditLedger {
    pub const fn new() -> Self {
        const NONE_BLOCK: Option<AuditBlock> = None;
        let genesis_block = AuditBlock::empty(0, Blake3Hash::ZERO);
        Self {
            block_count: 0,
            blocks: [NONE_BLOCK; MAX_BLOCKS_IN_LEDGER],
            current_block: genesis_block,
        }
    }

    /// Records a system security event into the blockchain
    pub fn record_event(&mut self, event: AuditEvent) {
        if !self.current_block.add_event(event) {
            // Block full: seal it and link into the chain
            self.commit_current_block();
            self.current_block.add_event(event);
        }
    }

    /// Seals the current active block and begins a new block pointing to it
    pub fn commit_current_block(&mut self) -> Blake3Hash {
        let sealed_hash = self.current_block.seal();
        if self.block_count < MAX_BLOCKS_IN_LEDGER {
            self.blocks[self.block_count] = Some(self.current_block);
            self.block_count += 1;
        }

        // Advance to next block pointing to current block hash
        let next_index = self.current_block.index + 1;
        self.current_block = AuditBlock::empty(next_index, sealed_hash);
        sealed_hash
    }

    /// Cryptographically verifies the entire ledger chain from Genesis to Head.
    /// Returns true if and only if no historical logs were tampered with.
    pub fn verify_integrity(&self) -> bool {
        let mut expected_prev_hash = Blake3Hash::ZERO;

        for i in 0..self.block_count {
            if let Some(ref block) = self.blocks[i] {
                // Check block chain continuity
                if block.prev_block_hash != expected_prev_hash {
                    return false;
                }

                // Verify block hash matches sealed contents
                let mut recomputed_block = *block;
                let valid_hash = recomputed_block.seal();
                if valid_hash != block.block_hash {
                    return false;
                }

                expected_prev_hash = block.block_hash;
            }
        }

        // Verify current open block links to latest sealed block
        if self.block_count > 0 {
            if self.current_block.prev_block_hash != expected_prev_hash {
                return false;
            }
        }

        true
    }
}
