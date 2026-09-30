"""Differential BLAKE2b vectors from Python's hashlib (the reference
BLAKE2 code CPython bundles).

    python3 tests/crypto/tools/blake2b_diff.py --seed blake2b-diff-1 --count 240

Writes tests/crypto/vectors/blake2b-diff.txt, fields: outlen key msg out.
Message lengths: 0 to 31, both sides of one, two and three 128-byte
blocks, then drawn below 700; digest lengths drawn from 1 to 64; keys
empty for a third of the cases and otherwise 1 to 64 bytes. Everything
comes from SHAKE256 of the seed (hashfam_util.det_bytes), so the file
regenerates byte for byte.
"""
import argparse
import hashlib
import sys

from hashfam_util import det_bytes, det_int, hx, write


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    s = args.seed
    lengths = list(range(32))
    for k in (1, 2, 3):
        lengths += [128 * k - 1, 128 * k, 128 * k + 1]
    i = 0
    while len(lengths) < args.count:
        lengths.append(det_int(f"{s}:len:{i}", 700))
        i += 1
    lines = []
    for i, n in enumerate(lengths[: args.count]):
        msg = det_bytes(f"{s}:msg:{i}", n)
        outlen = 1 + det_int(f"{s}:outlen:{i}", 64)
        keylen = 0 if det_int(f"{s}:keyed:{i}", 3) == 0 else 1 + det_int(f"{s}:keylen:{i}", 64)
        key = det_bytes(f"{s}:key:{i}", keylen)
        out = hashlib.blake2b(msg, digest_size=outlen, key=key).digest()
        lines.append(f"{outlen} {hx(key)} {hx(msg)} {out.hex()}")
    write("blake2b-diff.txt", [
        f"source: Python {sys.version.split()[0]} hashlib.blake2b",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/blake2b_diff.py --seed {args.seed} --count {args.count}",
        "fields: outlen key msg out",
    ], lines)


if __name__ == "__main__":
    main()
