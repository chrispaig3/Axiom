"""Differential HMAC vectors from Python's hmac and hashlib modules.

    python3 tests/crypto/tools/hmac_diff.py --seed hmac-diff-1 --count 120

Writes tests/crypto/vectors/hmac-diff.txt, fields: alg key msg tag, with
`alg` 256 or 512. Each algorithm gets `count` cases: key lengths on both
sides of the block length (and of twice it), then drawn from 1 to 300;
message lengths drawn below 400. Everything comes from SHAKE256 of the
seed (hashfam_util.det_bytes), so the file regenerates byte for byte.
"""
import argparse
import hashlib
import hmac
import sys

from hashfam_util import det_bytes, det_int, hx, write


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    lines = []
    for alg, block in (("256", 64), ("512", 128)):
        s = f"{args.seed}:{alg}"
        keylens = [1, 2, 16, 31, 32, 33, 63, 64, 65, block - 1, block, block + 1, 2 * block, 2 * block + 1]
        i = 0
        while len(keylens) < args.count:
            keylens.append(1 + det_int(f"{s}:keylen:{i}", 300))
            i += 1
        for i, kl in enumerate(keylens[: args.count]):
            key = det_bytes(f"{s}:key:{i}", kl)
            msg = det_bytes(f"{s}:msg:{i}", det_int(f"{s}:msglen:{i}", 400))
            tag = hmac.new(key, msg, getattr(hashlib, "sha" + alg)).digest()
            lines.append(f"{alg} {hx(key)} {hx(msg)} {tag.hex()}")
    write("hmac-diff.txt", [
        f"source: Python {sys.version.split()[0]} hmac and hashlib",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/hmac_diff.py --seed {args.seed} --count {args.count}",
        "fields: alg key msg tag",
    ], lines)


if __name__ == "__main__":
    main()
