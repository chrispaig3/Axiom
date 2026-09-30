"""Differential SHA-2 vectors from Python's hashlib (OpenSSL's SHA-2).

    python3 tests/crypto/tools/sha2_diff.py --seed sha2-diff-1 --count 160

Writes tests/crypto/vectors/sha2-diff.txt, fields: alg msg md, with
`alg` 256, 384 or 512. Each algorithm gets `count` messages: every
length from 0 to 139 (both sides of every block and padding boundary
for 64- and 128-byte blocks), then lengths drawn below 1100. Messages
and lengths come from SHAKE256 of the seed (hashfam_util.det_bytes),
so the file regenerates byte for byte.
"""
import argparse
import hashlib
import ssl
import sys

from hashfam_util import det_bytes, det_lengths, hx, write


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    lines = []
    for alg in ("256", "384", "512"):
        for i, n in enumerate(det_lengths(f"{args.seed}:{alg}", args.count, 140, 1100)):
            msg = det_bytes(f"{args.seed}:{alg}:msg:{i}", n)
            md = hashlib.new(f"sha{alg}", msg).digest()
            lines.append(f"{alg} {hx(msg)} {md.hex()}")
    write("sha2-diff.txt", [
        f"source: Python {sys.version.split()[0]} hashlib ({ssl.OPENSSL_VERSION})",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/sha2_diff.py --seed {args.seed} --count {args.count}",
        "fields: alg msg md",
    ], lines)


if __name__ == "__main__":
    main()
