"""Shared helpers for the ML-KEM vector scripts.

`fetch` downloads a pinned source and refuses bytes whose SHA-256 is
not the one recorded; set MLKEM_CACHE to a directory to keep the
downloads between runs (they are stored under their digest, since
several ACVP files share a name). `write` writes a vector file.
"""
import hashlib
import os
import sys
import urllib.request

VECTORS = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "vectors"))
SETS = {"ML-KEM-512": 2, "ML-KEM-768": 3, "ML-KEM-1024": 4}
NAMES = {2: "512", 3: "768", 4: "1024"}


def fetch(url, sha256):
    """The bytes at `url`, refused unless their SHA-256 is `sha256`."""
    cache = os.environ.get("MLKEM_CACHE")
    path = os.path.join(cache, sha256) if cache else None
    if path and os.path.exists(path):
        with open(path, "rb") as f:
            data = f.read()
    else:
        req = urllib.request.Request(url, headers={"User-Agent": "axiom-vectors"})
        with urllib.request.urlopen(req, timeout=300) as r:
            data = r.read()
        if path:
            os.makedirs(cache, exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
    got = hashlib.sha256(data).hexdigest()
    if got != sha256:
        sys.exit(f"{url}: sha256 is {got}, expected {sha256}")
    return data


def hx(b):
    """Bytes as a vector field: lower-case hex, or `-` when empty."""
    return b.hex() if b else "-"


def write(name, header, lines):
    """Write tests/crypto/vectors/<name>: `# ` header lines, then one
    case per line, LF endings."""
    path = os.path.join(VECTORS, name)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        for h in header:
            f.write(f"# {h}\n")
        for line in lines:
            f.write(line + "\n")
    print(f"{path}: {len(lines)} cases, {os.path.getsize(path)} bytes")


def params(k):
    """(ek, dk, ciphertext) lengths for ML-KEM with this k."""
    du, dv = (11, 5) if k == 4 else (10, 4)
    return 384 * k + 32, 768 * k + 96, 32 * (du * k + dv)


def split_dk(dk, k):
    """dk_PKE, ek, H(ek), z of an expanded decapsulation key."""
    return dk[:384 * k], dk[384 * k:768 * k + 32], dk[768 * k + 32:768 * k + 64], dk[768 * k + 64:]
