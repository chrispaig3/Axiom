"""Shared helpers for the ML-DSA vector scripts: fetch a pinned source,
check its SHA-256, write a vector file in the format tests/crypto/Kat.ax
reads, and FIPS 204's message formatting.

Python 3.12 standard library only. Set MLDSA_CACHE to a directory to
read sources from there (named by the last part of their URL, with
the parent directory's name in front when that is ambiguous) instead
of downloading them; the SHA-256 is checked either way.
"""
import hashlib
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
VECTORS = os.path.normpath(os.path.join(HERE, "..", "vectors"))

# Lengths of the encodings (FIPS 204, Table 2), by parameter set.
PK_BYTES = {44: 1312, 65: 1952, 87: 2592}
SK_BYTES = {44: 2560, 65: 4032, 87: 4896}
SIG_BYTES = {44: 2420, 65: 3309, 87: 4627}


def fetch(url, sha256, cache_name=None):
    """The bytes at `url`, refused unless their SHA-256 is `sha256`."""
    cache = os.environ.get("MLDSA_CACHE")
    name = cache_name or url.rstrip("/").split("/")[-1]
    if cache and os.path.exists(os.path.join(cache, name)):
        with open(os.path.join(cache, name), "rb") as f:
            data = f.read()
    else:
        req = urllib.request.Request(url, headers={"User-Agent": "axiom-vectors"})
        with urllib.request.urlopen(req, timeout=300) as r:
            data = r.read()
        if cache:
            os.makedirs(cache, exist_ok=True)
            with open(os.path.join(cache, name), "wb") as f:
                f.write(data)
    got = hashlib.sha256(data).hexdigest()
    if got != sha256:
        sys.exit(f"{url}: sha256 is {got}, expected {sha256}")
    return data


def hx(b):
    """Bytes as a vector field: lower-case hex, or `-` when empty."""
    return b.hex() if b else "-"


def sha(b):
    """The SHA-256 of `b` in hex: how a vector file carries a long
    expected output the test recomputes."""
    return hashlib.sha256(b).hexdigest()


def write(name, header, lines):
    """Write tests/crypto/vectors/<name>: `# ` header lines, then one
    case per line, LF endings."""
    path = os.path.join(VECTORS, name)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        for h in header:
            f.write(f"# {h}\n")
        for line in lines:
            f.write(line + "\n")
    print(f"{path}: {len(lines)} lines, {os.path.getsize(path)} bytes")


def det_bytes(label, n):
    """`n` bytes from SHAKE256 of `label`: the same on every run."""
    return hashlib.shake_256(label.encode()).digest(n)


def pure_mprime(ctx, msg):
    """M' for pure ML-DSA (FIPS 204 Algorithm 2 step 10)."""
    return bytes([0, len(ctx)]) + ctx + msg


# The DER encodings of the hash functions' OIDs and the pre-hash each
# computes (FIPS 204 Algorithm 4 and section 5.4.1).
_NIST_HASH = bytes.fromhex("06096086480165030402")
PREHASH = {
    "SHA2-256": (1, lambda m: hashlib.sha256(m).digest()),
    "SHA2-384": (2, lambda m: hashlib.sha384(m).digest()),
    "SHA2-512": (3, lambda m: hashlib.sha512(m).digest()),
    "SHA2-224": (4, lambda m: hashlib.sha224(m).digest()),
    "SHA2-512/224": (5, lambda m: hashlib.new("sha512_224", m).digest()),
    "SHA2-512/256": (6, lambda m: hashlib.new("sha512_256", m).digest()),
    "SHA3-224": (7, lambda m: hashlib.sha3_224(m).digest()),
    "SHA3-256": (8, lambda m: hashlib.sha3_256(m).digest()),
    "SHA3-384": (9, lambda m: hashlib.sha3_384(m).digest()),
    "SHA3-512": (10, lambda m: hashlib.sha3_512(m).digest()),
    "SHAKE-128": (11, lambda m: hashlib.shake_128(m).digest(32)),
    "SHAKE-256": (12, lambda m: hashlib.shake_256(m).digest(64)),
}


def prehash_mprime(ctx, msg, alg):
    """M' for HashML-DSA (FIPS 204 Algorithm 4 steps 10-23)."""
    arc, ph = PREHASH[alg]
    return bytes([1, len(ctx)]) + ctx + _NIST_HASH + bytes([arc]) + ph(msg)
