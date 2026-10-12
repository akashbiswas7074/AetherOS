//! Hardware-efficient BLAKE3 256-bit cryptographic hasher for bare-metal CasFS.
//! Operates in `#![no_std]` with zero heap allocations.

pub const BLAKE3_KEY_LEN: usize = 32;
pub const BLAKE3_OUT_LEN: usize = 32;
pub const BLAKE3_BLOCK_LEN: usize = 64;
pub const BLAKE3_CHUNK_LEN: usize = 1024;

const IV: [u32; 8] = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
];

const MSG_PERMUTATION: [usize; 16] = [
    2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8,
];

// Flags
const CHUNK_START: u32 = 1 << 0;
const CHUNK_END: u32 = 1 << 1;
const ROOT: u32 = 1 << 3;

#[inline(always)]
fn g(state: &mut [u32; 16], a: usize, b: usize, c: usize, d: usize, mx: u32, my: u32) {
    state[a] = state[a].wrapping_add(state[b]).wrapping_add(mx);
    state[d] = (state[d] ^ state[a]).rotate_right(16);
    state[c] = state[c].wrapping_add(state[d]);
    state[b] = (state[b] ^ state[c]).rotate_right(12);
    state[a] = state[a].wrapping_add(state[b]).wrapping_add(my);
    state[d] = (state[d] ^ state[a]).rotate_right(8);
    state[c] = state[c].wrapping_add(state[d]);
    state[b] = (state[b] ^ state[c]).rotate_right(7);
}

#[inline(always)]
fn round(state: &mut [u32; 16], m: &[u32; 16]) {
    g(state, 0, 4, 8, 12, m[0], m[1]);
    g(state, 1, 5, 9, 13, m[2], m[3]);
    g(state, 2, 6, 10, 14, m[4], m[5]);
    g(state, 3, 7, 11, 15, m[6], m[7]);
    g(state, 0, 5, 10, 15, m[8], m[9]);
    g(state, 1, 6, 11, 12, m[10], m[11]);
    g(state, 2, 7, 8, 13, m[12], m[13]);
    g(state, 3, 4, 9, 14, m[14], m[15]);
}

fn compress(
    cv: &[u32; 8],
    block: &[u8; 64],
    block_len: u32,
    counter: u64,
    flags: u32,
) -> [u32; 16] {
    let mut m = [0u32; 16];
    for i in 0..16 {
        m[i] = u32::from_le_bytes([
            block[i * 4],
            block[i * 4 + 1],
            block[i * 4 + 2],
            block[i * 4 + 3],
        ]);
    }

    let mut state = [
        cv[0], cv[1], cv[2], cv[3],
        cv[4], cv[5], cv[6], cv[7],
        IV[0], IV[1], IV[2], IV[3],
        counter as u32, (counter >> 32) as u32, block_len, flags,
    ];

    let mut msg = m;
    for _ in 0..7 {
        round(&mut state, &msg);
        let mut permuted = [0u32; 16];
        for j in 0..16 {
            permuted[j] = msg[MSG_PERMUTATION[j]];
        }
        msg = permuted;
    }

    for i in 0..8 {
        state[i] ^= state[i + 8];
        state[i + 8] ^= cv[i];
    }

    state
}

/// 256-bit BLAKE3 hash digest
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Default)]
pub struct Blake3Hash(pub [u8; 32]);

impl Blake3Hash {
    pub const ZERO: Self = Self([0u8; 32]);

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    /// Formats hash as a hex string (for debug output)
    pub fn write_hex<W: core::fmt::Write>(&self, w: &mut W) -> core::fmt::Result {
        const HEX_CHARS: &[u8; 16] = b"0123456789abcdef";
        for byte in self.0.iter() {
            let _ = w.write_char(HEX_CHARS[(byte >> 4) as usize] as char);
            let _ = w.write_char(HEX_CHARS[(byte & 0x0f) as usize] as char);
        }
        Ok(())
    }
}

impl core::fmt::Debug for Blake3Hash {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        for byte in self.0.iter().take(4) {
            write!(f, "{:02x}", byte)?;
        }
        write!(f, "..")?;
        for byte in self.0.iter().skip(28) {
            write!(f, "{:02x}", byte)?;
        }
        Ok(())
    }
}

/// Computes BLAKE3 hash for arbitrary byte slice
pub fn hash(data: &[u8]) -> Blake3Hash {
    let mut cv = IV;
    let total_len = data.len();

    if total_len == 0 {
        let block = [0u8; 64];
        let out = compress(&cv, &block, 0, 0, CHUNK_START | CHUNK_END | ROOT);
        let mut digest = [0u8; 32];
        for i in 0..8 {
            digest[i * 4..(i + 1) * 4].copy_from_slice(&out[i].to_le_bytes());
        }
        return Blake3Hash(digest);
    }

    let mut offset = 0;
    let mut block_idx = 0u64;

    while offset < total_len {
        let remaining = total_len - offset;
        let chunk_take = remaining.min(64);
        let mut block = [0u8; 64];
        block[..chunk_take].copy_from_slice(&data[offset..offset + chunk_take]);

        let mut flags = 0;
        if offset == 0 {
            flags |= CHUNK_START;
        }
        if offset + chunk_take >= total_len {
            flags |= CHUNK_END | ROOT;
        }

        let out = compress(&cv, &block, chunk_take as u32, block_idx, flags);
        if flags & ROOT != 0 {
            let mut digest = [0u8; 32];
            for i in 0..8 {
                digest[i * 4..(i + 1) * 4].copy_from_slice(&out[i].to_le_bytes());
            }
            return Blake3Hash(digest);
        } else {
            for i in 0..8 {
                cv[i] = out[i];
            }
        }

        offset += chunk_take;
        block_idx += 1;
    }

    Blake3Hash::ZERO
}
