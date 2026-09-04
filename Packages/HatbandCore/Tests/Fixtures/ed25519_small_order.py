#!/usr/bin/env python3
"""Derives the small-order Ed25519 public keys CardSignature.verify rejects.

Pure-Python edwards25519 after ed25519.cr.yp.to (affine, RFC 8032 §5.1),
independent of swift-crypto. Takes a random curve point outside the prime
subgroup, multiplies by L to land in the torsion subgroup, and enumerates its
multiples: the eight points whose order divides 8. Prints their canonical
encodings, checks them against libsodium's blocklist (ed25519_ref10.c, sign
bit masked, less its two non-canonical entries p and p + 1), and confirms
that random keys are not small order.
"""
import os
import sys

p = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
d = (-121665 * pow(121666, p - 2, p)) % p
I = pow(2, (p - 1) // 4, p)


def xrecover(y):
    xx = (y * y - 1) * pow(d * y * y + 1, p - 2, p)
    x = pow(xx, (p + 3) // 8, p)
    if (x * x - xx) % p != 0:
        x = (x * I) % p
    if (x * x - xx) % p != 0:
        return None
    if x % 2 != 0:
        x = p - x
    return x


def on_curve(P):
    x, y = P
    return (-x * x + y * y - 1 - d * x * x * y * y) % p == 0


def add(P, Q):
    x1, y1 = P
    x2, y2 = Q
    x3 = (x1 * y2 + x2 * y1) * pow(1 + d * x1 * x2 * y1 * y2, p - 2, p)
    y3 = (y1 * y2 + x1 * x2) * pow(1 - d * x1 * x2 * y1 * y2, p - 2, p)
    return (x3 % p, y3 % p)


def mul(P, e):
    if e == 0:
        return (0, 1)
    Q = mul(P, e // 2)
    Q = add(Q, Q)
    if e & 1:
        Q = add(Q, P)
    return Q


def encode(P):
    x, y = P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def decode(s):
    n = int.from_bytes(s, "little")
    y = n & ((1 << 255) - 1)
    if y >= p:
        return None
    x = xrecover(y)
    if x is None:
        return None
    if x == 0 and n >> 255:
        return None
    if (x & 1) != (n >> 255):
        x = p - x
    P = (x, y)
    return P if on_curve(P) else None


def random_point(rng):
    while True:
        P = decode(rng(32))
        if P is not None:
            return P


BASE = decode(bytes([0x58] + [0x66] * 31))
assert mul(BASE, L) == (0, 1), "base point has order L"

# libsodium's blocklist with the sign bit clear; p and p + 1 (non-canonical
# encodings of 0 and 1) left out.
LIBSODIUM = [
    bytes(32),
    bytes([1]) + bytes(31),
    bytes.fromhex("26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05"),
    bytes.fromhex("c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a"),
    bytes([0xEC]) + bytes([0xFF] * 30) + bytes([0x7F]),
]


def masked(s):
    return s[:31] + bytes([s[31] & 0x7F])


def main():
    rng = os.urandom
    while True:
        T = mul(random_point(rng), L)
        if mul(T, 4) != (0, 1):
            break  # T has order 8, so its multiples are the whole torsion subgroup
    torsion = sorted({encode(mul(T, k)) for k in range(8)})
    assert len(torsion) == 8
    for s in torsion:
        P = decode(s)
        assert P is not None and mul(P, 8) == (0, 1)
        assert encode(P) == s, "canonical"
        assert masked(s) in LIBSODIUM, s.hex()
    for y in LIBSODIUM:
        assert any(masked(s) == y for s in torsion), y.hex()
    for _ in range(32):
        A = decode(encode(mul(BASE, int.from_bytes(rng(32), "little") % L or 1)))
        assert mul(A, 8) != (0, 1) and mul(A, L) == (0, 1)
    for s in torsion:
        print(s.hex())
    print("ok: 8 torsion points match libsodium; 32 random keys are not small order", file=sys.stderr)


if __name__ == "__main__":
    main()
