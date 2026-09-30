"""Shared helpers for the X25519 and Ed25519 vector scripts: fetch a
pinned source, check its SHA-256, write a vector file in the format
tests/crypto/Kat.ax reads, draw deterministic bytes from a seed, and a
small reference model of the arithmetic (Python integers, written from
RFC 7748 section 5 and RFC 8032 section 5.1) for the vectors that test
the field, scalar and group layers directly.

Python 3.12 standard library only. Set CURVE25519_CACHE to a directory
to read sources from there (named by the last part of their URL)
instead of downloading them; the SHA-256 is checked either way.
"""
import hashlib
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
VECTORS = os.path.normpath(os.path.join(HERE, "..", "vectors"))


def fetch(url, sha256):
    """The bytes at `url`, refused unless their SHA-256 is `sha256`."""
    cache = os.environ.get("CURVE25519_CACHE")
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
    """`n` bytes from SHAKE256 of `label`: the same on every run."""
    return hashlib.shake_256(label.encode()).digest(n)


def det_int(label, below):
    """An integer in 0..below-1 from SHAKE256 of `label` (64 extra bits
    make the bias negligible)."""
    k = (below.bit_length() + 64 + 7) // 8
    return int.from_bytes(det_bytes(label, k), "little") % below


# ------------------------------------------------------------------
# The reference model.
# ------------------------------------------------------------------
P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = (-121665 * pow(121666, P - 2, P)) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def le(n, size=32):
    return n.to_bytes(size, "little")


def from_le(b):
    return int.from_bytes(b, "little")


# X25519, RFC 7748 section 5 (the pseudo-code, with the cswap written
# as a branch: this model is for generating answers, not for secrets).
def x25519(k, u):
    k = bytearray(k)
    k[0] &= 248
    k[31] &= 127
    k[31] |= 64
    k = from_le(k)
    x1 = from_le(u) & ((1 << 255) - 1)
    x2, z2, x3, z3, swap = 1, 0, x1, 1, 0
    for t in range(254, -1, -1):
        kt = (k >> t) & 1
        swap ^= kt
        if swap:
            x2, x3 = x3, x2
            z2, z3 = z3, z2
        swap = kt
        A = (x2 + z2) % P
        AA = A * A % P
        B = (x2 - z2) % P
        BB = B * B % P
        E = (AA - BB) % P
        C = (x3 + z3) % P
        Dd = (x3 - z3) % P
        DA = Dd * A % P
        CB = C * B % P
        x3 = (DA + CB) ** 2 % P
        z3 = x1 * (DA - CB) ** 2 % P
        x2 = AA * BB % P
        z2 = E * (AA + 121665 * E) % P
    if swap:
        x2, x3 = x3, x2
        z2, z3 = z3, z2
    return le(x2 * pow(z2, P - 2, P) % P)


# Edwards25519 in extended coordinates (X, Y, Z, T), RFC 8032 5.1.4.
def pt_add(p, q):
    A = (p[1] - p[0]) * (q[1] - q[0]) % P
    B = (p[1] + p[0]) * (q[1] + q[0]) % P
    C = 2 * p[3] * q[3] * D % P
    Dd = 2 * p[2] * q[2] % P
    E, F, G, H = B - A, Dd - C, Dd + C, B + A
    return (E * F % P, G * H % P, F * G % P, E * H % P)


def pt_mul(s, p):
    q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            q = pt_add(q, p)
        p = pt_add(p, p)
        s >>= 1
    return q


def pt_equal(p, q):
    return (p[0] * q[2] - q[0] * p[2]) % P == 0 and (p[1] * q[2] - q[1] * p[2]) % P == 0


def recover_x(y, sign):
    """x for this y and sign bit, or None (RFC 8032 5.1.3 steps 2-4)."""
    if y >= P:
        return None
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P != 0:
        x = x * SQRT_M1 % P
    if (x * x - x2) % P != 0:
        return None
    if (x & 1) != sign:
        x = P - x
    return x


def pt_decode(b):
    """The point a 32-byte encoding names, or None when it is not a
    strict (canonical, on-curve) encoding."""
    if len(b) != 32:
        return None
    y = from_le(b) & ((1 << 255) - 1)
    sign = b[31] >> 7
    x = recover_x(y, sign)
    if x is None:
        return None
    return (x, y, 1, x * y % P)


def pt_encode(p):
    zi = pow(p[2], P - 2, P)
    x, y = p[0] * zi % P, p[1] * zi % P
    return le(y | ((x & 1) << 255))


BASE_Y = 4 * pow(5, P - 2, P) % P
BASE = (recover_x(BASE_Y, 0), BASE_Y, 1, recover_x(BASE_Y, 0) * BASE_Y % P)


def sha512_modL(*parts):
    return from_le(hashlib.sha512(b"".join(parts)).digest()) % L


def ed25519_expand(seed):
    h = hashlib.sha512(seed).digest()
    a = bytearray(h[:32])
    a[0] &= 248
    a[31] &= 127
    a[31] |= 64
    return from_le(a), h[32:]


def ed25519_public(seed):
    a, _ = ed25519_expand(seed)
    return pt_encode(pt_mul(a, BASE))


def ed25519_sign(seed, msg):
    a, prefix = ed25519_expand(seed)
    A = pt_encode(pt_mul(a, BASE))
    r = sha512_modL(prefix, msg)
    R = pt_encode(pt_mul(r, BASE))
    k = sha512_modL(R, A, msg)
    return R + le((r + k * a) % L)


def ed25519_verify(pub, msg, sig):
    """RFC 8032 5.1.7 with the cofactorless equation [S]B = R + [k]A,
    strict decoding of A and R, and S < L."""
    if len(pub) != 32 or len(sig) != 64:
        return False
    A = pt_decode(pub)
    R = pt_decode(sig[:32])
    s = from_le(sig[32:])
    if A is None or R is None or s >= L:
        return False
    k = sha512_modL(sig[:32], pub, msg)
    return pt_equal(pt_mul(s, BASE), pt_add(R, pt_mul(k, A)))
