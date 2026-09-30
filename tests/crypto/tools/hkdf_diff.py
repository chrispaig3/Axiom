"""Differential HKDF vectors, RFC 5869 computed with Python's hmac and
hashlib modules (the standard library has no HKDF of its own; the ten
lines below are section 2 as written).

    python3 tests/crypto/tools/hkdf_diff.py --seed hkdf-diff-1 --count 60

Writes tests/crypto/vectors/hkdf-diff.txt, fields: alg ikm salt info len
okm, with `alg` 256 or 512. Each algorithm gets `count` cases: output
lengths on both sides of one and two blocks and the maximum of 255
blocks, then drawn from 1 to 300; salts empty, on both sides of the
block length, or drawn below 200 bytes; IKM 1 to 100 bytes; info 0 to
100 bytes. Everything comes from SHAKE256 of the seed
(hashfam_util.det_bytes), so the file regenerates byte for byte.
"""
import argparse
import hashlib
import hmac
import sys

from hashfam_util import det_bytes, det_int, hx, write


def hkdf(h, ikm, salt, info, n):
    prk = hmac.new(salt or bytes(h().digest_size), ikm, h).digest()
    t, okm, i = b"", b"", 1
    while len(okm) < n:
        t = hmac.new(prk, t + info + bytes([i]), h).digest()
        okm += t
        i += 1
    return okm[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    lines = []
    for alg, hl, block in (("256", 32, 64), ("512", 64, 128)):
        s = f"{args.seed}:{alg}"
        h = getattr(hashlib, "sha" + alg)
        outlens = [1, hl - 1, hl, hl + 1, 2 * hl, 2 * hl + 1, 255 * hl]
        saltlens = [0, block - 1, block, block + 1, 0, 1, 0]
        i = 0
        while len(outlens) < args.count:
            outlens.append(1 + det_int(f"{s}:len:{i}", 300))
            saltlens.append(det_int(f"{s}:saltlen:{i}", 200))
            i += 1
        for i in range(args.count):
            ikm = det_bytes(f"{s}:ikm:{i}", 1 + det_int(f"{s}:ikmlen:{i}", 100))
            salt = det_bytes(f"{s}:salt:{i}", saltlens[i])
            info = det_bytes(f"{s}:info:{i}", det_int(f"{s}:infolen:{i}", 101))
            okm = hkdf(h, ikm, salt, info, outlens[i])
            lines.append(f"{alg} {hx(ikm)} {hx(salt)} {hx(info)} {outlens[i]} {okm.hex()}")
    write("hkdf-diff.txt", [
        f"source: Python {sys.version.split()[0]} hmac and hashlib, RFC 5869 section 2 in this script",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/hkdf_diff.py --seed {args.seed} --count {args.count}",
        "fields: alg ikm salt info len okm",
    ], lines)


if __name__ == "__main__":
    main()
