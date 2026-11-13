"""Counter-based random numbers: Philox4x32-10 (Salmon et al., 2011).

A draw is a pure function of (seed, stream, entity id, step). There is no generator
state, so results do not depend on evaluation order or thread count. Only 32/64-bit
integer operations are used, which makes the function trivial to reproduce bit for
bit in any language.
"""

from __future__ import annotations

_M0 = 0xD2511F53
_M1 = 0xCD9E8D57
_W0 = 0x9E3779B9
_W1 = 0xBB67AE85
_MASK32 = 0xFFFFFFFF
_TWO_POW_MINUS_53 = 2.0**-53


def philox4x32_10(counter: tuple[int, int, int, int], key: tuple[int, int]) -> tuple[int, int, int, int]:
    """The Philox4x32 bijection with 10 rounds. All words are unsigned 32-bit."""
    c0, c1, c2, c3 = counter
    k0, k1 = key
    for round_index in range(10):
        if round_index:
            k0 = (k0 + _W0) & _MASK32
            k1 = (k1 + _W1) & _MASK32
        p0 = _M0 * c0
        p1 = _M1 * c2
        hi0, lo0 = p0 >> 32, p0 & _MASK32
        hi1, lo1 = p1 >> 32, p1 & _MASK32
        c0, c1, c2, c3 = hi1 ^ c1 ^ k0, lo1, hi0 ^ c3 ^ k1, lo0
    return c0, c1, c2, c3


def uniform(seed: int, stream: int, entity: int, step: int) -> float:
    """A real in [0, 1) with 53 random bits.

    counter = (entity low word, entity high word, step, stream); key = (seed low, seed high).
    The first two output words form a 64-bit integer whose top 53 bits are scaled by 2^-53.
    """
    out = philox4x32_10(
        (entity & _MASK32, (entity >> 32) & _MASK32, step & _MASK32, stream & _MASK32),
        (seed & _MASK32, (seed >> 32) & _MASK32),
    )
    bits = (out[0] << 32) | out[1]
    return (bits >> 11) * _TWO_POW_MINUS_53


def fnv1a32(text: str) -> int:
    """FNV-1a, 32-bit, over the UTF-8 bytes. Used to turn a stream name into a stream id."""
    h = 0x811C9DC5
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 0x01000193) & _MASK32
    return h
