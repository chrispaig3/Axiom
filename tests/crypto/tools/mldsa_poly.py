"""Vectors for the hazardous layer under ML-DSA (Crypto.MlDsaPoly): the
NTT, ring multiplication, rounding, hints, bit encodings and sampling,
each answer computed with Python integers straight from FIPS 204's
algorithms (not from the reference implementation the module ports).

    python3 tests/crypto/tools/mldsa_poly.py --seed mldsa-poly-1 --count 4

Writes tests/crypto/vectors/mldsa-poly.txt. Polynomial inputs are
derived from a label, which the test derives the same way: the 768
bytes of SHAKE256(label), read as 256 three-byte little-endian values,
each reduced modulo the range the operation wants (see `poly_from`).
Outputs are compared as the SHA-256 of their encoding: each
coefficient reduced to [0, q) and written as three little-endian bytes.

  ntt label out              NTT(a) (Algorithm 41)
  invntt label out           2^32 NTT^-1(a) (Algorithm 42, times the
                             Montgomery factor the module leaves)
  mul label out              a b in Z_q[X]/(X^256 + 1), by schoolbook
                             multiplication, a = poly(label:a), b = poly(label:b)
  p2r label out              a1 then a0 of Power2Round (Algorithm 35)
  decompose g2 label out     a1 then a0 of Decompose (Algorithm 36)
  usehint g2 label out       UseHint (Algorithm 40) of r = poly(label)
                             with hints poly(label:h) taken modulo 2
  makehint g2 a0 a1 ones out the reference's hint rule on the given low
                             and high parts, checked against MakeHint
                             (Algorithm 39) of the values they came from
  pack bits b label out      BitPack of b - (x mod 2^bits) (Algorithm 17)
  simplepack bits label out  SimpleBitPack of x mod 2^bits (Algorithm 16)
  uniform rho i j out        RejNTTPoly(rho || j || i) (Algorithm 30)
  eta seed nonce eta out     RejBoundedPoly(seed || nonce) (Algorithm 31)
  mask seed nonce g1 out     one polynomial of ExpandMask (Algorithm 34)
  challenge ctilde tau out   SampleInBall (Algorithm 29)
  hint k omega enc out       HintBitUnpack (Algorithm 21): the hints'
                             encoding, or 00 when it must be refused
"""
import argparse
import hashlib

from mldsa_util import det_bytes, write

Q = 8380417
N = 256


def brv8(k):
    return int(format(k, "08b")[::-1], 2)


ZETAS = [pow(1753, brv8(k), Q) for k in range(N)]


def poly_from(label, m):
    b = hashlib.shake_256(label.encode()).digest(3 * N)
    return [int.from_bytes(b[3 * i:3 * i + 3], "little") % m for i in range(N)]


def enc(p):
    return b"".join((c % Q).to_bytes(3, "little") for c in p)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def ntt(w):
    w = [c % Q for c in w]
    m, ln = 0, 128
    while ln >= 1:
        start = 0
        while start < N:
            m += 1
            z = ZETAS[m]
            for j in range(start, start + ln):
                t = z * w[j + ln] % Q
                w[j + ln] = (w[j] - t) % Q
                w[j] = (w[j] + t) % Q
            start += 2 * ln
        ln //= 2
    return w


def intt(w):
    w = [c % Q for c in w]
    m, ln = 256, 1
    while ln < N:
        start = 0
        while start < N:
            m -= 1
            z = -ZETAS[m]
            for j in range(start, start + ln):
                t = w[j]
                w[j] = (t + w[j + ln]) % Q
                w[j + ln] = (t - w[j + ln]) % Q
                w[j + ln] = z * w[j + ln] % Q
            start += 2 * ln
        ln *= 2
    return [8347681 * c % Q for c in w]


def ring_mul(a, b):
    c = [0] * N
    for i in range(N):
        for j in range(N):
            k = i + j
            if k < N:
                c[k] += a[i] * b[j]
            else:
                c[k - N] -= a[i] * b[j]
    return [x % Q for x in c]


def mod_pm(r, a):
    r0 = r % a
    return r0 - a if r0 > a // 2 else r0


def power2round(r):
    rp = r % Q
    r0 = mod_pm(rp, 1 << 13)
    return (rp - r0) >> 13, r0


def decompose(r, g2):
    rp = r % Q
    r0 = mod_pm(rp, 2 * g2)
    if rp - r0 == Q - 1:
        return 0, r0 - 1
    return (rp - r0) // (2 * g2), r0


def high_bits(r, g2):
    return decompose(r, g2)[0]


def use_hint(h, r, g2):
    m = (Q - 1) // (2 * g2)
    r1, r0 = decompose(r, g2)
    if h == 1 and r0 > 0:
        return (r1 + 1) % m
    if h == 1:
        return (r1 - 1) % m
    return r1


def bit_pack(vals, bits):
    acc = 0
    for i, v in enumerate(vals):
        acc |= v << (bits * i)
    return acc.to_bytes(32 * bits, "little")


def rej_ntt_poly(rho, i, j):
    stream = hashlib.shake_128(rho + bytes([j, i])).digest(168 * 40)
    out, pos = [], 0
    while len(out) < N:
        z = stream[pos] | stream[pos + 1] << 8 | (stream[pos + 2] & 127) << 16
        pos += 3
        if z < Q:
            out.append(z)
    return out


def half_byte(b, eta):
    if eta == 2 and b < 15:
        return 2 - b % 5
    if eta == 4 and b < 9:
        return 4 - b
    return None


def rej_bounded_poly(seed, nonce, eta):
    stream = hashlib.shake_256(seed + nonce.to_bytes(2, "little")).digest(136 * 20)
    out, pos = [], 0
    while len(out) < N:
        for z in (half_byte(stream[pos] & 15, eta), half_byte(stream[pos] >> 4, eta)):
            if z is not None and len(out) < N:
                out.append(z)
        pos += 1
    return out


def expand_mask_poly(seed, nonce, g1):
    bits = 1 + (g1 - 1).bit_length()
    v = int.from_bytes(hashlib.shake_256(seed + nonce.to_bytes(2, "little")).digest(32 * bits), "little")
    return [g1 - ((v >> (bits * i)) & ((1 << bits) - 1)) for i in range(N)]


def sample_in_ball(ctilde, tau):
    stream = hashlib.shake_256(ctilde).digest(136 * 20)
    signs = int.from_bytes(stream[:8], "little")
    pos, c = 8, [0] * N
    for i in range(N - tau, N):
        j = stream[pos]
        pos += 1
        while j > i:
            j = stream[pos]
            pos += 1
        c[i] = c[j]
        c[j] = -1 if (signs >> (i + tau - N)) & 1 else 1
    return c


def hint_unpack(y, k, omega):
    h = [[0] * N for _ in range(k)]
    index = 0
    for i in range(k):
        if y[omega + i] < index or y[omega + i] > omega:
            return None
        first = index
        while index < y[omega + i]:
            if index > first and y[index - 1] >= y[index]:
                return None
            h[i][y[index]] = 1
            index += 1
    for i in range(index, omega):
        if y[i] != 0:
            return None
    return h


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    s = args.seed
    lines = []
    for i in range(args.count):
        lb = f"{s}:{i}"
        a = poly_from(lb, Q)
        lines.append(f"ntt {lb} {sha(enc(ntt(a)))}")
        lines.append(f"invntt {lb} {sha(enc([c * (1 << 32) % Q for c in intt(a)]))}")
        lines.append(f"mul {lb} {sha(enc(ring_mul(poly_from(lb + ':a', Q), poly_from(lb + ':b', Q))))}")
        # the ring product through the transform agrees with schoolbook
        assert intt([x * y % Q for x, y in zip(ntt(poly_from(lb + ':a', Q)), ntt(poly_from(lb + ':b', Q)))]) == \
            ring_mul(poly_from(lb + ':a', Q), poly_from(lb + ':b', Q))
        pr = [power2round(c) for c in a]
        lines.append(f"p2r {lb} {sha(enc([x for x, _ in pr]) + enc([y for _, y in pr]))}")
        for g2 in (95232, 261888):
            d = [decompose(c, g2) for c in a]
            lines.append(f"decompose {g2} {lb} {sha(enc([x for x, _ in d]) + enc([y for _, y in d]))}")
            hs = poly_from(lb + ":h", 2)
            lines.append(f"usehint {g2} {lb} {sha(enc([use_hint(h, r, g2) for h, r in zip(hs, a)]))}")
            # MakeHint as signing uses it: u = w - c s2 with small low
            # part, d = c t0 below gamma2; the reference's rule sees
            # a0 = LowBits(u) + d and a1 = HighBits(u).
            beta = 78 if g2 == 95232 else 196
            us = [x % Q for x in poly_from(lb + ":u", Q)]
            ds = [x % (2 * g2 - 1) - (g2 - 1) for x in poly_from(lb + ":d", Q)]
            a0s, a1s, want = [], [], []
            for u, dd in zip(us, ds):
                r1, r0 = decompose(u, g2)
                if abs(r0) >= g2 - beta:
                    u = (u - r0) % Q
                    r1, r0 = decompose(u, g2)
                a0s.append(r0 + dd)
                a1s.append(r1)
                want.append(int(high_bits(u + dd, g2) != high_bits(u, g2)))
            lines.append(f"makehint {g2} {enc(a0s).hex()} {enc(a1s).hex()} {sum(want)} {sha(enc(want))}")
        for bits, b in ((3, 2), (4, 4), (13, 4096), (18, 131072), (20, 524288)):
            x = poly_from(f"{lb}:pack{bits}", 1 << bits)
            lines.append(f"pack {bits} {b} {lb} {sha(bit_pack(x, bits))}")
        for bits in (4, 6, 10):
            x = poly_from(f"{lb}:spack{bits}", 1 << bits)
            lines.append(f"simplepack {bits} {lb} {sha(bit_pack(x, bits))}")
        rho = det_bytes(lb + ":rho", 32)
        lines.append(f"uniform {rho.hex()} {i % 8} {(3 * i) % 7} {sha(enc(rej_ntt_poly(rho, i % 8, (3 * i) % 7)))}")
        seed64 = det_bytes(lb + ":seed", 64)
        for eta in (2, 4):
            lines.append(f"eta {seed64.hex()} {i * 7} {eta} {sha(enc(rej_bounded_poly(seed64, i * 7, eta)))}")
        for g1 in (131072, 524288):
            lines.append(f"mask {seed64.hex()} {300 * i + 5} {g1} {sha(enc(expand_mask_poly(seed64, 300 * i + 5, g1)))}")
        for clen, tau in ((32, 39), (48, 49), (64, 60)):
            ct = det_bytes(f"{lb}:ctilde{clen}", clen)
            lines.append(f"challenge {ct.hex()} {tau} {sha(enc(sample_in_ball(ct, tau)))}")
    # hint encodings: well formed, then each way Algorithm 21 refuses one
    k, omega = 4, 80
    good = bytes([1, 5, 200] + [0] * 77 + [3, 3, 3, 3])
    cases = [
        good,
        bytes([7] + [0] * 79 + [0, 1, 1, 1]),
        bytes(list(range(80)) + [20, 40, 60, 80]),
        bytes([1, 5, 200] + [0] * 77 + [3, 2, 3, 3]),     # a count that goes down
        bytes([1, 5, 200] + [0] * 77 + [3, 3, 3, 81]),    # a count past omega
        bytes([5, 1, 200] + [0] * 77 + [3, 3, 3, 3]),     # positions out of order
        bytes([5, 5, 200] + [0] * 77 + [3, 3, 3, 3]),     # a repeated position
        bytes([1, 5, 200, 9] + [0] * 76 + [3, 3, 3, 3]),  # nonzero padding
        bytes([1, 5, 200] + [0] * 76 + [9, 3, 3, 3, 3]),  # nonzero last padding byte
    ]
    for c in cases:
        h = hint_unpack(c, k, omega)
        out = "00" if h is None else sha(b"".join(enc(p) for p in h))
        lines.append(f"hint {k} {omega} {c.hex()} {out}")
    write("mldsa-poly.txt", [
        "source: Python integers and hashlib SHAKE, from the algorithms of FIPS 204 (tests/crypto/tools/mldsa_poly.py)",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/mldsa_poly.py --seed {args.seed} --count {args.count}",
        "fields: op, the operation's inputs, then the expected output (see the script)",
    ], lines)


if __name__ == "__main__":
    main()
