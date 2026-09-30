"""Differential ML-DSA vectors from the OpenSSL command line.

    python3 tests/crypto/tools/mldsa_openssl.py --seed mldsa-openssl-1 --count 16

Writes tests/crypto/vectors/mldsa-openssl.txt. For each parameter set
and case i below `count`, a 32-byte key seed, a context of seeded
length (0, 255 and lengths between), a message of 1 to 2000 bytes, and
for even i a 32-byte rnd, all from SHAKE256 of the seed string:

  sign set seed ctx msg rnd pkSha256 skSha256 sigSha256
      `openssl genpkey -pkeyopt hexseed:` makes the key, whose public
      key and expanded private key are read from its DER encodings;
      `openssl pkeyutl -sign -rawin` signs with -pkeyopt
      hexcontext-string, and either deterministic:1 (odd i, `rnd` is
      `-`) or hextest-entropy set to rnd (even i).
  verify set seed ctx msg sig
      for i below 2, a hedged signature OpenSSL made with its own
      randomness, in full.

`pkeyutl` refuses an empty message, so none is empty; the ACVP and
Wycheproof files cover that case. Set OPENSSL to choose the binary
(default /opt/homebrew/bin/openssl).
"""
import argparse
import os
import subprocess
import sys
import tempfile

from mldsa_util import PK_BYTES, SK_BYTES, SIG_BYTES, det_bytes, hx, sha, write

OPENSSL = os.environ.get("OPENSSL", "/opt/homebrew/bin/openssl")


def run(*args):
    return subprocess.run([OPENSSL, *args], check=True, capture_output=True).stdout


def der_items(b):
    """The (tag, value) pairs of a DER sequence of items at the top of `b`."""
    out, i = [], 0
    while i < len(b):
        tag, n = b[i], b[i + 1]
        i += 2
        if n & 0x80:
            k = n & 0x7F
            n = int.from_bytes(b[i:i + k], "big")
            i += k
        out.append((tag, b[i:i + n]))
        i += n
    return out


def private_parts(der):
    """(seed, expanded private key) from OpenSSL's PKCS#8 encoding, which
    carries both (the `both` choice of the ML-DSA private key)."""
    _, pkcs8 = der_items(der)[0]
    items = der_items(pkcs8)
    _, inner = items[2]
    tag, both = der_items(inner)[0]
    assert tag == 0x30, "expected the seed-and-key form"
    (t1, seed), (t2, sk) = der_items(both)
    assert t1 == 0x04 and t2 == 0x04
    return seed, sk


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    version = run("version").decode().strip()
    lines = []
    with tempfile.TemporaryDirectory() as tmp:
        key, msgf, sigf = (os.path.join(tmp, n) for n in ("key.der", "msg.bin", "sig.bin"))
        for s in (44, 65, 87):
            for i in range(args.count):
                label = f"{args.seed}:{s}:{i}"
                seed = det_bytes(label + ":seed", 32)
                clen = [0, 255][i] if i < 2 else det_bytes(label + ":clen", 1)[0]
                ctx = det_bytes(label + ":ctx", clen)
                msg = det_bytes(label + ":msg", 1 + int.from_bytes(det_bytes(label + ":mlen", 2), "little") % 2000)
                run("genpkey", "-algorithm", f"ML-DSA-{s}", "-pkeyopt", f"hexseed:{seed.hex()}",
                    "-outform", "DER", "-out", key)
                got_seed, sk = private_parts(open(key, "rb").read())
                pk = run("pkey", "-inform", "DER", "-in", key, "-pubout", "-outform", "DER")[-PK_BYTES[s]:]
                if got_seed != seed or len(sk) != SK_BYTES[s]:
                    sys.exit(f"ML-DSA-{s} case {i}: unexpected private key encoding")
                with open(msgf, "wb") as f:
                    f.write(msg)
                ctxopt = ["-pkeyopt", f"hexcontext-string:{ctx.hex()}"] if ctx else []
                if i % 2 == 0:
                    rnd = det_bytes(label + ":rnd", 32)
                    mode = ["-pkeyopt", f"hextest-entropy:{rnd.hex()}"]
                else:
                    rnd = b""
                    mode = ["-pkeyopt", "deterministic:1"]
                run("pkeyutl", "-sign", "-rawin", "-inkey", key, "-keyform", "DER", "-in", msgf,
                    "-out", sigf, *ctxopt, *mode)
                sig = open(sigf, "rb").read()
                if len(sig) != SIG_BYTES[s]:
                    sys.exit(f"ML-DSA-{s} case {i}: a {len(sig)}-byte signature")
                lines.append(f"sign {s} {seed.hex()} {hx(ctx)} {hx(msg)} {hx(rnd)} {sha(pk)} {sha(sk)} {sha(sig)}")
                if i < 2:
                    run("pkeyutl", "-sign", "-rawin", "-inkey", key, "-keyform", "DER", "-in", msgf,
                        "-out", sigf, *ctxopt)
                    lines.append(f"verify {s} {seed.hex()} {hx(ctx)} {hx(msg)} {open(sigf, 'rb').read().hex()}")
    write("mldsa-openssl.txt", [
        f"source: {version}, {OPENSSL} genpkey, pkey and pkeyutl -sign -rawin",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/mldsa_openssl.py --seed {args.seed} --count {args.count}",
        "fields: sign set seed ctx msg rnd pkSha256 skSha256 sigSha256 | verify set seed ctx msg sig",
    ], lines)


if __name__ == "__main__":
    main()
