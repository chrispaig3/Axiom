"""Shared helpers for the AES, GCM, ChaCha20 and AEAD vector scripts.

Every script downloads its pinned source through `fetch`, which
refuses bytes whose SHA-256 is not the one recorded, and writes its
vector file through `write`. Set AEAD_CACHE to a directory to keep the
downloads between runs.
"""
import hashlib
import os
import sys
import urllib.request

VECTORS = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "vectors"))


def fetch(url, sha256):
    """The bytes at `url`, refused unless their SHA-256 is `sha256`."""
    cache = os.environ.get("AEAD_CACHE")
    name = url.rstrip("/").split("/")[-1]
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


def det_bytes(label, n):
    """`n` bytes from SHAKE256 of `label`: the same on every run and
    every Python version."""
    return hashlib.shake_256(label.encode()).digest(n)


def det_int(label, bound):
    """An integer in 0..bound-1 drawn from `label` (bound < 2^32)."""
    return int.from_bytes(det_bytes(label, 8), "little") % bound
