//! Counter-based random numbers: Philox4x32-10 (Salmon et al., 2011).
//!
//! A draw is a pure function of (seed, stream, entity id, step). There is no generator
//! state, so results do not depend on evaluation order or thread count.

const M0: u32 = 0xD251_1F53;
const M1: u32 = 0xCD9E_8D57;
const W0: u32 = 0x9E37_79B9;
const W1: u32 = 0xBB67_AE85;

/// The Philox4x32 bijection with 10 rounds.
#[inline]
pub fn philox4x32_10(mut c: [u32; 4], mut k: [u32; 2]) -> [u32; 4] {
    for round in 0..10 {
        if round > 0 {
            k[0] = k[0].wrapping_add(W0);
            k[1] = k[1].wrapping_add(W1);
        }
        let p0 = (M0 as u64) * (c[0] as u64);
        let p1 = (M1 as u64) * (c[2] as u64);
        c = [(p1 >> 32) as u32 ^ c[1] ^ k[0], p1 as u32, (p0 >> 32) as u32 ^ c[3] ^ k[1], p0 as u32];
    }
    c
}

/// A real in [0, 1) with 53 random bits.
///
/// counter = (entity low word, entity high word, step, stream); key = (seed low, seed high).
/// The first two output words form a 64-bit integer whose top 53 bits are scaled by 2^-53.
#[inline]
pub fn uniform(seed: u64, stream: u32, entity: u64, step: u32) -> f64 {
    let out = philox4x32_10([entity as u32, (entity >> 32) as u32, step, stream], [seed as u32, (seed >> 32) as u32]);
    let bits = ((out[0] as u64) << 32) | out[1] as u64;
    (bits >> 11) as f64 * (1.0 / 9_007_199_254_740_992.0)
}

/// FNV-1a, 32-bit, over the UTF-8 bytes. Turns a stream name into a stream id.
pub fn fnv1a32(text: &str) -> u32 {
    let mut h: u32 = 0x811C_9DC5;
    for byte in text.bytes() {
        h ^= byte as u32;
        h = h.wrapping_mul(0x0100_0193);
    }
    h
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn philox_known_answers() {
        // Vectors from the Random123 reference distribution.
        assert_eq!(philox4x32_10([0; 4], [0; 2]), [0x6627_E8D5, 0xE169_C58D, 0xBC57_AC4C, 0x9B00_DBD8]);
        assert_eq!(philox4x32_10([u32::MAX; 4], [u32::MAX; 2]), [0x408F_276D, 0x41C8_3B0E, 0xA20B_C7C6, 0x6D54_51FD]);
        assert_eq!(
            philox4x32_10([0x243F_6A88, 0x85A3_08D3, 0x1319_8A2E, 0x0370_7344], [0xA409_3822, 0x299F_31D0]),
            [0xD16C_FE09, 0x94FD_CCEB, 0x5001_E420, 0x2412_6EA1]
        );
    }

    #[test]
    fn uniform_matches_the_oracle() {
        assert_eq!(uniform(1, 2, 3, 4), 0.282_889_125_902_804_7);
        assert_eq!(fnv1a32("hiring"), 0x991C_3B50);
        assert_eq!(fnv1a32(""), 0x811C_9DC5);
    }
}
