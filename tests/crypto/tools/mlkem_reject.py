"""Implicit-rejection vectors for ML-KEM decapsulation.

    python3 tests/crypto/tools/mlkem_reject.py

For each parameter set, two key pairs from seeds drawn from SHAKE256
of a label (seed `mlkem-reject-1`) and one valid ciphertext each,
made by OpenSSL 3.6 (`openssl genpkey -pkeyopt hexseed`, then
`openssl pkeyutl -encap -pkeyopt hexikme` with an m drawn the same
way). Each ciphertext is then corrupted seven ways: one bit flipped in
the first byte, in the last byte of c1, in the first byte of c2 and in
the last byte; every byte set to zero; every byte set to 0xff; and
the two halves c1 and c2 of two different ciphertexts spliced.

The expected secret for each is K-bar = J(z || c) = SHAKE256(z || c)
to 32 bytes, computed here with Python's hashlib from z (the second
half of the seed) - independently of the code under test - and checked
against OpenSSL's own decapsulation of the same corrupted ciphertext.
The file also carries each valid ciphertext with OpenSSL's secret, so
a decapsulation that answered K-bar for everything would fail.

Fields: set seed kind c k, `kind` being `valid` or the corruption.
"""
import hashlib
import os
import subprocess
import sys
import tempfile

from mlkem_util import hx, params, write

OPENSSL = "/opt/homebrew/bin/openssl"
SEED = "mlkem-reject-1"


def run(args):
    r = subprocess.run([OPENSSL] + args, capture_output=True)
    if r.returncode != 0:
        sys.exit(f"openssl {' '.join(args)}: exit {r.returncode}\n{r.stderr.decode(errors='replace')}")
    return r.stdout


def main():
    version = run(["version"]).decode().strip()
    lines = []
    with tempfile.TemporaryDirectory() as tmp:
        priv, pub = os.path.join(tmp, "k.pem"), os.path.join(tmp, "p.pem")
        ctf, ssf = os.path.join(tmp, "c"), os.path.join(tmp, "s")
        for (n, k) in (("512", 2), ("768", 3), ("1024", 4)):
            ct_len = params(k)[2]
            c1_len = 32 * (11 if k == 4 else 10) * k
            made = []
            for i in range(2):
                seed = hashlib.shake_256(f"{SEED}/{n}/{i}".encode()).digest(64)
                m = hashlib.shake_256(f"{SEED}/{n}/{i}/m".encode()).digest(32)
                run(["genpkey", "-algorithm", f"ML-KEM-{n}", "-pkeyopt", f"hexseed:{seed.hex()}", "-out", priv])
                run(["pkey", "-in", priv, "-pubout", "-out", pub])
                run(["pkeyutl", "-encap", "-pubin", "-inkey", pub, "-pkeyopt", f"hexikme:{m.hex()}",
                     "-out", ctf, "-secret", ssf])
                c, s = open(ctf, "rb").read(), open(ssf, "rb").read()
                made.append((seed, c))
                lines.append(f"{n} {hx(seed)} valid {hx(c)} {hx(s)}")
            for i, (seed, c) in enumerate(made):
                other = made[1 - i][1]
                bad = []
                for (name, pos) in (("flip-first", 0), ("flip-c1-last", c1_len - 1),
                                    ("flip-c2-first", c1_len), ("flip-last", ct_len - 1)):
                    x = bytearray(c)
                    x[pos] ^= 1
                    bad.append((name, bytes(x)))
                bad.append(("zeros", bytes(ct_len)))
                bad.append(("ones", b"\xff" * ct_len))
                bad.append(("spliced", c[:c1_len] + other[c1_len:]))
                run(["genpkey", "-algorithm", f"ML-KEM-{n}", "-pkeyopt", f"hexseed:{seed.hex()}", "-out", priv])
                for (name, x) in bad:
                    kbar = hashlib.shake_256(seed[32:] + x).digest(32)
                    open(ctf, "wb").write(x)
                    run(["pkeyutl", "-decap", "-inkey", priv, "-in", ctf, "-secret", ssf])
                    if open(ssf, "rb").read() != kbar:
                        sys.exit(f"ML-KEM-{n} {name}: OpenSSL does not answer J(z || c)")
                    lines.append(f"{n} {hx(seed)} {name} {hx(x)} {hx(kbar)}")
    write("mlkem-reject.txt", [
        f"source: J(z || c) by Python hashlib SHAKE256; ciphertexts and a cross-check by {version}",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/mlkem_reject.py (seed {SEED})",
        "fields: set seed kind c k",
    ], lines)


if __name__ == "__main__":
    main()
