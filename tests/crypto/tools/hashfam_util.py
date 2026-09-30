"""Shared helpers for the hash-family vector scripts (SHA-2, SHA-3,
SHAKE, BLAKE2b, HMAC, HKDF): fetch a pinned source, check its SHA-256,
and write a vector file in the format tests/crypto/Kat.ax reads.

Python 3.12 standard library only. Set HASHFAM_CACHE to a directory to
read sources from there (named by the last part of their URL) instead of
downloading them; the SHA-256 is checked either way.
"""
import hashlib
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
VECTORS = os.path.normpath(os.path.join(HERE, "..", "vectors"))


def fetch(url, sha256):
    """The bytes at `url`, refused unless their SHA-256 is `sha256`."""
    cache = os.environ.get("HASHFAM_CACHE")
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


def rsp_records(text):
    """The records of a NIST CAVP .rsp file: each a dict of the
    `Key = value` lines between blank lines, with the current `[...]`
    section header under the key `section`."""
    records, cur, section = [], {}, ""
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if not line:
            if cur:
                records.append(cur)
                cur = {}
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            if not cur:
                cur["section"] = section
            cur[k.strip()] = v.strip()
    if cur:
        records.append(cur)
    return records


def det_bytes(label, n):
    """`n` bytes determined by `label` alone: SHAKE256 of the label. The
    differential scripts draw their messages and lengths from this, so
    a file regenerates byte for byte on any Python 3."""
    return hashlib.shake_256(label.encode("utf-8")).digest(n)


def det_int(label, bound):
    """An integer in 0..bound-1 determined by `label` (a 64-bit draw
    reduced modulo `bound`; the slight bias does not matter for choosing
    test lengths)."""
    return int.from_bytes(det_bytes(label, 8), "little") % bound


def det_lengths(seed, count, small, bound):
    """Message lengths for a differential file: every length below
    `small`, then `count - small` lengths drawn below `bound`."""
    out = list(range(min(small, count)))
    for i in range(small, count):
        out.append(det_int(f"{seed}:len:{i}", bound))
    return out


def rfc_fields(text, names):
    """The `Name = hex` fields of an RFC's test-vector text, in order, as
    (name, bytes) pairs. The `=` may be missing (RFC 4231's test case 3
    has none). A value may continue on following lines indented to where
    its hex began; a `0x` prefix and a trailing parenthetical such as
    `(20 bytes)` are dropped. Page headers and footers match neither
    form and are skipped."""
    import re
    out = []
    cur = None
    col = 0
    pat = re.compile(r"^   (%s) *=? *(0x)?([0-9a-fA-F]+)" % "|".join(re.escape(n) for n in names))
    for line in text.splitlines():
        m = pat.match(line)
        if m:
            if cur:
                out.append(cur)
            cur = [m.group(1), m.group(3)]
            col = m.start(3) - (2 if m.group(2) else 0)
            continue
        if cur is not None:
            cont = re.match(r"^ {%d}(0x)?([0-9a-fA-F]+)(\s|$)" % col, line)
            if cont and line[:col].strip() == "":
                cur[1] += cont.group(2)
                continue
            out.append(cur)
            cur = None
    if cur:
        out.append(cur)
    return [(n, bytes.fromhex(h)) for n, h in out]
