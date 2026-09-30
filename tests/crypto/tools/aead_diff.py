"""Differential vectors for AES, GHASH, AES-GCM, ChaCha20, Poly1305 and
ChaCha20-Poly1305, answered by implementations that share no code with
Axiom's.

    python3 tests/crypto/tools/aead_diff.py [--work DIR]

Inputs are drawn deterministically from SHAKE256 of a label (seed
`aead-diff-1`), with lengths that start at the block-boundary cases
(0, 1, 15, 16, 17, ... 300) and continue at random in 0..300. The
answers come from two oracles:

- OpenSSL 3.6 (`/opt/homebrew/bin/openssl enc`): AES-128/192/256-ECB
  for aes-ecb-diff.txt and ChaCha20 for chacha20-diff.txt (OpenSSL's
  16-byte ChaCha20 IV is the 32-bit counter, little-endian, then the
  12-byte nonce).
- RustCrypto, built offline from the cargo registry cache into a
  throwaway project under DIR (default: a temporary directory):
  aes-gcm 0.10.3, chacha20poly1305 0.10.1, poly1305 0.8.0 and
  ghash 0.5.1, for aes-gcm-diff.txt, chacha20-poly1305-diff.txt,
  poly1305-diff.txt and gcm-ghash-diff.txt.

The tool versions go into each file's `source:` line.
"""
import argparse
import os
import subprocess
import sys
import tempfile

from aead_util import det_bytes, det_int, hx, write

SEED = "aead-diff-1"
OPENSSL = "/opt/homebrew/bin/openssl"
EDGES = [0, 1, 15, 16, 17, 31, 32, 33, 47, 48, 63, 64, 65, 127, 128, 129, 191, 192, 255, 256, 257, 300]

CARGO_TOML = """[package]
name = "aead-oracle"
version = "0.1.0"
edition = "2021"
publish = false

[dependencies]
aes-gcm = "=0.10.3"
chacha20poly1305 = "=0.10.1"
poly1305 = "=0.8.0"
ghash = "=0.5.1"

[workspace]
"""

MAIN_RS = r"""
// One request per line on stdin, one answer per line on stdout; hex,
// with `-` for an empty field.
//   gcm KEY NONCE AAD PT     -> CT TAG
//   cp KEY NONCE AAD PT      -> CT TAG
//   poly KEY MSG             -> TAG
//   ghash H DATA             -> Y      (blocks zero-padded)
use std::io::{self, BufRead, Write};

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes128Gcm, Aes256Gcm, Nonce};
use chacha20poly1305::ChaCha20Poly1305;
use ghash::universal_hash::UniversalHash;

fn unhex(s: &str) -> Vec<u8> {
    if s == "-" {
        return Vec::new();
    }
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
}

fn hex(b: &[u8]) -> String {
    if b.is_empty() {
        return "-".to_string();
    }
    b.iter().map(|x| format!("{:02x}", x)).collect()
}

fn split(sealed: Vec<u8>) -> String {
    let n = sealed.len() - 16;
    format!("{} {}", hex(&sealed[..n]), hex(&sealed[n..]))
}

fn main() {
    let stdin = io::stdin();
    let mut out = io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        let f: Vec<&str> = line.split(' ').collect();
        let answer = match f[0] {
            "gcm" => {
                let key = unhex(f[1]);
                let nonce = unhex(f[2]);
                let (aad, msg) = (unhex(f[3]), unhex(f[4]));
                let p = Payload { msg: &msg, aad: &aad };
                let n = Nonce::from_slice(&nonce);
                split(if key.len() == 16 {
                    Aes128Gcm::new_from_slice(&key).unwrap().encrypt(n, p).unwrap()
                } else {
                    Aes256Gcm::new_from_slice(&key).unwrap().encrypt(n, p).unwrap()
                })
            }
            "cp" => {
                let key = unhex(f[1]);
                let nonce = unhex(f[2]);
                let (aad, msg) = (unhex(f[3]), unhex(f[4]));
                let p = Payload { msg: &msg, aad: &aad };
                let c = ChaCha20Poly1305::new_from_slice(&key).unwrap();
                split(c.encrypt(chacha20poly1305::Nonce::from_slice(&nonce), p).unwrap())
            }
            "poly" => {
                let key = unhex(f[1]);
                let msg = unhex(f[2]);
                hex(&poly1305::Poly1305::new_from_slice(&key).unwrap().compute_unpadded(&msg))
            }
            "ghash" => {
                let mut g = ghash::GHash::new_from_slice(&unhex(f[1])).unwrap();
                g.update_padded(&unhex(f[2]));
                hex(&g.finalize())
            }
            op => panic!("unknown request {op}"),
        };
        writeln!(out, "{}", answer).unwrap();
    }
}
"""


def run(cmd, data=None, cwd=None):
    r = subprocess.run(cmd, input=data, cwd=cwd, capture_output=True)
    if r.returncode != 0:
        sys.exit(f"{' '.join(cmd)}: exit {r.returncode}\n{r.stderr.decode(errors='replace')}")
    return r.stdout


def length(label, i):
    return EDGES[i] if i < len(EDGES) else det_int(f"{label}/len", 301)


def oracle(work):
    """Build the RustCrypto oracle under `work` and return a function
    that answers a list of request lines."""
    os.makedirs(os.path.join(work, "src"), exist_ok=True)
    with open(os.path.join(work, "Cargo.toml"), "w") as f:
        f.write(CARGO_TOML)
    with open(os.path.join(work, "src", "main.rs"), "w") as f:
        f.write(MAIN_RS)
    run(["cargo", "build", "--offline", "--release", "--quiet"], cwd=work)
    exe = os.path.join(work, "target", "release", "aead-oracle")

    def ask(requests):
        out = run([exe], ("\n".join(requests) + "\n").encode()).decode().split("\n")[:-1]
        if len(out) != len(requests):
            sys.exit(f"the oracle answered {len(out)} of {len(requests)} requests")
        return out
    return ask


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", help="directory for the RustCrypto oracle's cargo project")
    args = ap.parse_args()
    work = args.work or tempfile.mkdtemp(prefix="aead-oracle-")
    ask = oracle(work)
    ossl = run([OPENSSL, "version"]).decode().strip()
    rust = run(["rustc", "--version"]).decode().strip()
    gen = "sha256: - (generated, not downloaded)"
    extract = f"extract: tests/crypto/tools/aead_diff.py (seed {SEED})"

    # AES, the raw block cipher: 1..9 blocks under each key size.
    lines = []
    for i in range(60):
        lab = f"{SEED}/aes-ecb/{i}"
        klen = (16, 24, 32)[i % 3]
        key = det_bytes(f"{lab}/key", klen)
        pt = det_bytes(f"{lab}/pt", 16 * (1 + det_int(f"{lab}/n", 9)))
        ct = run([OPENSSL, "enc", f"-aes-{klen * 8}-ecb", "-nopad", "-K", key.hex()], pt)
        lines.append(f"{hx(key)} {hx(pt)} {hx(ct)}")
    write("aes-ecb-diff.txt", [f"source: {ossl}, openssl enc -aes-N-ecb -nopad", gen, extract,
                               "fields: key plaintext ciphertext"], lines)

    # ChaCha20 from a random counter, kept clear of the 32-bit wrap.
    lines = []
    for i in range(60):
        lab = f"{SEED}/chacha20/{i}"
        key = det_bytes(f"{lab}/key", 32)
        nonce = det_bytes(f"{lab}/nonce", 12)
        n = length(lab, i)
        ctr = (0, 1, 4294967290)[i] if i < 3 else det_int(f"{lab}/ctr", 4294967290)
        pt = det_bytes(f"{lab}/pt", n)
        iv = ctr.to_bytes(4, "little") + nonce
        ct = run([OPENSSL, "enc", "-chacha20", "-K", key.hex(), "-iv", iv.hex()], pt) if n else b""
        lines.append(f"{hx(key)} {hx(nonce)} {ctr} {hx(pt)} {hx(ct)}")
    write("chacha20-diff.txt", [f"source: {ossl}, openssl enc -chacha20", gen, extract,
                                "fields: key nonce counter plaintext ciphertext"], lines)

    # GHASH over zero-padded blocks.
    cases = []
    for i in range(80):
        lab = f"{SEED}/ghash/{i}"
        cases.append((det_bytes(f"{lab}/h", 16), det_bytes(f"{lab}/data", length(lab, i) if i < 22 else det_int(f"{lab}/len", 201))))
    ans = ask([f"ghash {hx(h)} {hx(d)}" for (h, d) in cases])
    write("gcm-ghash-diff.txt", [f"source: RustCrypto ghash 0.5.1 ({rust}), GHash::update_padded", gen, extract,
                                 "fields: h data y"],
          [f"{hx(h)} {hx(d)} {y}" for ((h, d), y) in zip(cases, ans)])

    # Poly1305, including keys whose r clamps to its largest value and
    # whose s is all ones.
    cases = []
    for i in range(100):
        lab = f"{SEED}/poly1305/{i}"
        key = det_bytes(f"{lab}/key", 32)
        if i % 10 == 1:
            key = b"\xff" * 32
        elif i % 10 == 2:
            key = key[:16] + b"\xff" * 16
        cases.append((key, det_bytes(f"{lab}/msg", length(lab, i))))
    ans = ask([f"poly {hx(k)} {hx(m)}" for (k, m) in cases])
    write("poly1305-diff.txt", [f"source: RustCrypto poly1305 0.8.0 ({rust}), Poly1305::compute_unpadded", gen,
                                extract, "fields: key msg tag"],
          [f"{hx(k)} {hx(m)} {t}" for ((k, m), t) in zip(cases, ans)])

    # The two AEADs.
    for (name, op, keylens, src) in [
        ("aes-gcm-diff.txt", "gcm", (16, 32), "RustCrypto aes-gcm 0.10.3"),
        ("chacha20-poly1305-diff.txt", "cp", (32,), "RustCrypto chacha20poly1305 0.10.1"),
    ]:
        cases = []
        for i in range(200 if op == "gcm" else 150):
            lab = f"{SEED}/{op}/{i}"
            klen = keylens[i % len(keylens)]
            key = det_bytes(f"{lab}/key", klen)
            nonce = det_bytes(f"{lab}/nonce", 12)
            aad = det_bytes(f"{lab}/aad", det_int(f"{lab}/aadlen", 81))
            pt = det_bytes(f"{lab}/pt", length(lab, i // len(keylens)))
            cases.append((key, nonce, aad, pt))
        ans = ask([f"{op} {hx(k)} {hx(n)} {hx(a)} {hx(p)}" for (k, n, a, p) in cases])
        write(name, [f"source: {src} ({rust}), Aead::encrypt", gen, extract,
                     "fields: key nonce aad plaintext ciphertext tag"],
              [f"{hx(k)} {hx(n)} {hx(a)} {hx(p)} {r}" for ((k, n, a, p), r) in zip(cases, ans)])


if __name__ == "__main__":
    main()
