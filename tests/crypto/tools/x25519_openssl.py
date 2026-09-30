"""Differential X25519 vectors from the OpenSSL command line.

    python3 tests/crypto/tools/x25519_openssl.py --seed x25519-openssl-1 --count 96

Writes tests/crypto/vectors/x25519-openssl.txt, fields: priv pub peer
shared. For case i, `priv` is 32 bytes from SHAKE256 of the seed, `pub`
is the public key OpenSSL derives for it, `peer` is either OpenSSL's
public key for a second seeded private key (even i) or 32 seeded bytes
used as a u-coordinate as they stand, bit 255 included (odd i), and
`shared` is what `openssl pkeyutl -derive` answers. Set OPENSSL to
choose the binary (default /opt/homebrew/bin/openssl).
"""
import argparse
import os
import subprocess
import sys
import tempfile

from curve25519_util import det_bytes, write, x25519

OPENSSL = os.environ.get("OPENSSL", "/opt/homebrew/bin/openssl")
PKCS8_PREFIX = bytes.fromhex("302e020100300506032b656e04220420")
SPKI_PREFIX = bytes.fromhex("302a300506032b656e032100")


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
        peer = os.path.join(tmp, "peer.der")
        pubf = os.path.join(tmp, "pub.der")
        for i in range(args.count):
            priv = det_bytes(f"{args.seed}:priv:{i}", 32)
            with open(key, "wb") as f:
                f.write(PKCS8_PREFIX + priv)
            run("pkey", "-inform", "DER", "-in", key, "-pubout", "-outform", "DER", "-out", pubf)
            spki = open(pubf, "rb").read()
            assert spki.startswith(SPKI_PREFIX) and len(spki) == 44
            pub = spki[12:]
            if i % 2 == 0:
                other = det_bytes(f"{args.seed}:other:{i}", 32)
                with open(peer, "wb") as f:
                    f.write(PKCS8_PREFIX + other)
                run("pkey", "-inform", "DER", "-in", peer, "-pubout", "-outform", "DER", "-out", pubf)
                u = open(pubf, "rb").read()[12:]
            else:
                u = det_bytes(f"{args.seed}:u:{i}", 32)
            with open(peer, "wb") as f:
                f.write(SPKI_PREFIX + u)
            shared = run("pkeyutl", "-derive", "-inkey", key, "-keyform", "DER",
                         "-peerkey", peer, "-peerform", "DER")
            if len(shared) != 32:
                sys.exit(f"case {i}: OpenSSL answered {len(shared)} bytes")
            if x25519(priv, u) != shared or x25519(priv, (9).to_bytes(32, "little")) != pub:
                sys.exit(f"case {i}: OpenSSL and the reference model disagree")
            lines.append(f"{priv.hex()} {pub.hex()} {u.hex()} {shared.hex()}")
    write("x25519-openssl.txt", [
        f"source: {version}, {OPENSSL} pkey and pkeyutl -derive",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/x25519_openssl.py --seed {args.seed} --count {args.count}",
        "fields: priv pub peer shared",
    ], lines)


if __name__ == "__main__":
    main()
