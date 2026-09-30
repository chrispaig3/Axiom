"""Differential Ed25519 vectors from the OpenSSL command line.

    python3 tests/crypto/tools/ed25519_openssl.py --seed ed25519-openssl-1 --count 128

Writes tests/crypto/vectors/ed25519-openssl.txt, fields: seed pub msg
sig. For case i, `seed` is 32 bytes from SHAKE256 of the seed string
and `msg` is i + 1 bytes long for i below 64 (`pkeyutl` refuses an
empty message, which RFC 8032's TEST 1 covers), then a seeded length
from 1 to 3000; `pub` is the public key `openssl pkey` derives, and
`sig` what `openssl pkeyutl -sign -rawin` answers. Set OPENSSL to
choose the binary (default /opt/homebrew/bin/openssl).
"""
import argparse
import os
import subprocess
import sys
import tempfile

from curve25519_util import det_bytes, det_int, ed25519_public, ed25519_sign, hx, write

OPENSSL = os.environ.get("OPENSSL", "/opt/homebrew/bin/openssl")
PKCS8_PREFIX = bytes.fromhex("302e020100300506032b657004220420")
SPKI_PREFIX = bytes.fromhex("302a300506032b6570032100")


def run(*args):
    return subprocess.run([OPENSSL, *args], check=True, capture_output=True).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    version = run("version").decode().strip()
    lines = []
    with tempfile.TemporaryDirectory() as tmp:
        key = os.path.join(tmp, "key.der")
        pubf = os.path.join(tmp, "pub.der")
        msgf = os.path.join(tmp, "msg.bin")
        sigf = os.path.join(tmp, "sig.bin")
        for i in range(args.count):
            seed = det_bytes(f"{args.seed}:seed:{i}", 32)
            n = i + 1 if i < 64 else 1 + det_int(f"{args.seed}:len:{i}", 3000)
            msg = det_bytes(f"{args.seed}:msg:{i}", n)
            with open(key, "wb") as f:
                f.write(PKCS8_PREFIX + seed)
            with open(msgf, "wb") as f:
                f.write(msg)
            run("pkey", "-inform", "DER", "-in", key, "-pubout", "-outform", "DER", "-out", pubf)
            spki = open(pubf, "rb").read()
            assert spki.startswith(SPKI_PREFIX) and len(spki) == 44
            pub = spki[12:]
            run("pkeyutl", "-sign", "-rawin", "-inkey", key, "-keyform", "DER", "-in", msgf, "-out", sigf)
            sig = open(sigf, "rb").read()
            if len(sig) != 64:
                sys.exit(f"case {i}: OpenSSL answered {len(sig)} bytes")
            if ed25519_public(seed) != pub or ed25519_sign(seed, msg) != sig:
                sys.exit(f"case {i}: OpenSSL and the reference model disagree")
            lines.append(f"{seed.hex()} {pub.hex()} {hx(msg)} {sig.hex()}")
    write("ed25519-openssl.txt", [
        f"source: {version}, {OPENSSL} pkey and pkeyutl -sign -rawin",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/ed25519_openssl.py --seed {args.seed} --count {args.count}",
        "fields: seed pub msg sig",
    ], lines)


if __name__ == "__main__":
    main()
