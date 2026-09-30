"""Differential SHA-3 and SHAKE vectors from Python's hashlib.

    python3 tests/crypto/tools/sha3_diff.py --seed sha3-diff-1 --count 80

Writes, from SHAKE256 of the seed (hashfam_util.det_bytes), so the files
regenerate byte for byte:
  sha3-diff.txt   fields: alg msg md          (alg 224, 256, 384, 512)
  shake-diff.txt  fields: alg outlen msg output   (alg 128, 256)
Each algorithm gets `count` messages: lengths 0 to 31, the lengths on
both sides of one, two and three blocks of its rate, then lengths drawn
below 700. Each SHAKE case also draws its output length below 700, so
outputs cross squeeze-block boundaries.
"""
import argparse
import hashlib
import ssl
import sys

from hashfam_util import det_bytes, det_int, hx, write

RATES = {"224": 144, "256": 136, "384": 104, "512": 72, "s128": 168, "s256": 136}


def lengths(seed, rate, count):
    out = list(range(32))
    for k in (1, 2, 3):
        out += [k * rate - 1, k * rate, k * rate + 1]
    i = 0
    while len(out) < count:
        out.append(det_int(f"{seed}:len:{i}", 700))
        i += 1
    return out[:count]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    src = f"source: Python {sys.version.split()[0]} hashlib ({ssl.OPENSSL_VERSION})"
    extract = f"extract: tests/crypto/tools/sha3_diff.py --seed {args.seed} --count {args.count}"
    lines = []
    for alg in ("224", "256", "384", "512"):
        for i, n in enumerate(lengths(f"{args.seed}:{alg}", RATES[alg], args.count)):
            msg = det_bytes(f"{args.seed}:{alg}:msg:{i}", n)
            lines.append(f"{alg} {hx(msg)} {hashlib.new('sha3_' + alg, msg).hexdigest()}")
    write("sha3-diff.txt", [src, "sha256: - (generated, not downloaded)", extract,
                            "fields: alg msg md"], lines)
    lines = []
    for alg in ("128", "256"):
        for i, n in enumerate(lengths(f"{args.seed}:shake{alg}", RATES["s" + alg], args.count)):
            msg = det_bytes(f"{args.seed}:shake{alg}:msg:{i}", n)
            outlen = det_int(f"{args.seed}:shake{alg}:out:{i}", 700)
            out = hashlib.new("shake_" + alg, msg).digest(outlen)
            lines.append(f"{alg} {outlen} {hx(msg)} {hx(out)}")
    write("shake-diff.txt", [src, "sha256: - (generated, not downloaded)", extract,
                             "fields: alg outlen msg output"], lines)


if __name__ == "__main__":
    main()
