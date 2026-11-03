"""Writes Ed25519 differential cases with libsodium and OpenSSL verdicts.

Usage: python3 -I generate.py OUT.jsonl [COUNT_PER_KIND]
Each line: {"kind", "pk", "msg", "sig", "sodium", "openssl"} (hex fields).
Needs libsodium.so.23 and the `cryptography` package on the host.
"""
import ctypes
import hashlib
import json
import random
import sys

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey, Ed25519PublicKey)
from cryptography.hazmat.primitives.serialization import (
    Encoding, PublicFormat)

_sodium = ctypes.CDLL('libsodium.so.23')
assert _sodium.sodium_init() >= 0

P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def sodium(pk, msg, sig):
    return _sodium.crypto_sign_verify_detached(
        sig, msg, ctypes.c_ulonglong(len(msg)), pk) == 0


def openssl(pk, msg, sig):
    try:
        Ed25519PublicKey.from_public_bytes(pk).verify(sig, msg)
        return True
    except (InvalidSignature, ValueError):
        return False


def decode(s):
    y = int.from_bytes(s, 'little') & ((1 << 255) - 1)
    sign = s[31] >> 7
    if y >= P:
        return None
    u, v = (y * y - 1) % P, (D * y * y + 1) % P
    x = u * pow(v, 3, P) * pow(u * pow(v, 7, P), (P - 5) // 8, P) % P
    if v * x * x % P != u:
        if v * x * x % P != (-u) % P:
            return None
        x = x * SQRT_M1 % P
    if x == 0 and sign:
        return None
    if x & 1 != sign:
        x = P - x
    return (x, y, 1, x * y % P)


def encode(pt):
    x, y, z, _ = pt
    zi = pow(z, P - 2, P)
    x, y = x * zi % P, y * zi % P
    return (y | ((x & 1) << 255)).to_bytes(32, 'little')


def add(p, q):
    a = (p[1] - p[0]) * (q[1] - q[0]) % P
    b = (p[1] + p[0]) * (q[1] + q[0]) % P
    c = 2 * D * p[3] * q[3] % P
    d = 2 * p[2] * q[2] % P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % P, g * h % P, f * g % P, e * h % P)


def mul(k, pt):
    out = (0, 1, 1, 0)
    for bit in bin(k)[2:]:
        out = add(out, out)
        if bit == '1':
            out = add(out, pt)
    return out


def random_point(rng):
    while True:
        pt = decode(rng.randbytes(32))
        if pt:
            return pt


def torsion(rng):
    # [L]P has order dividing 8.
    return mul(L, random_point(rng))


def keypair(rng):
    sk = Ed25519PrivateKey.from_private_bytes(rng.randbytes(32))
    return sk, sk.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)


def flip(data, rng):
    out = bytearray(data)
    if out:
        out[rng.randrange(len(out))] ^= 1 << rng.randrange(8)
    return bytes(out)


def cases(rng, n):
    for _ in range(n):
        sk, pk = keypair(rng)
        msg = rng.randbytes(rng.randrange(0, 300))
        sig = sk.sign(msg)
        yield 'valid', pk, msg, sig
        yield 'flip-sig', pk, msg, flip(sig, rng)
        yield 'flip-msg', pk, flip(msg, rng) if msg else b'\x00', sig
        yield 'flip-pk', flip(pk, rng), msg, sig
        s = int.from_bytes(sig[32:], 'little')
        k = rng.randrange(1, 16)
        if s + k * L < 2**256:
            yield 's-plus-kL', pk, msg, sig[:32] + (s + k * L).to_bytes(32, 'little')
        yield 'random-sig', pk, msg, rng.randbytes(64)
        yield 'random-pk', rng.randbytes(32), msg, sig
        # Non-canonical y, where y + p still fits.
        y = int.from_bytes(pk, 'little') & ((1 << 255) - 1)
        if y < 19:
            yield 'noncanonical-pk', (y + P).to_bytes(32, 'little'), msg, sig
        t = torsion(rng)
        a = decode(pk)
        yield 'mixed-order-pk', encode(add(a, t)), msg, sig
        yield 'mixed-order-r', pk, msg, encode(add(decode(sig[:32]), t)) + sig[32:]
        # Small-order A and R with S = 0: [0]B = R + [k]A can hold.
        small_a, small_r = encode(torsion(rng)), encode(torsion(rng))
        yield 'small-a-small-r-s0', small_a, msg, small_r + bytes(32)
        yield 'small-a-random-s', small_a, msg, small_r + rng.randbytes(32)
        yield 'small-r', pk, msg, small_r + sig[32:]


def main():
    out, per = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 8000
    rng = random.Random(984)
    with open(out, 'w') as f:
        for kind, pk, msg, sig in cases(rng, per):
            f.write(json.dumps({
                'kind': kind, 'pk': pk.hex(), 'msg': msg.hex(), 'sig': sig.hex(),
                'sodium': sodium(pk, msg, sig), 'openssl': openssl(pk, msg, sig),
            }) + '\n')


main()
