"""Vectors for the hazardous layers under X25519 and Ed25519: field
arithmetic modulo 2^255 - 19, scalar arithmetic modulo L, and the
Edwards group, each answer computed with Python integers by the
reference model in curve25519_util.py.

    python3 tests/crypto/tools/curve25519_ref.py --seed curve25519-ref-1 --count 48

Writes three files. Operands are the edge values listed below, then
`count` values from SHAKE256 of the seed; every byte field is 32 bytes
little-endian unless it says otherwise.

  curve25519-field.txt   op a b out
      mul sq sq2 mul121666 inv pow22523 neg canon addmul submul isneg
      iszero. `a` and `b` are any 32 bytes; bit 255 is ignored, as
      fe25519FromBytes ignores it. `out` is the canonical result
      (isneg and iszero: one byte, 00 or 01).
  curve25519-scalar.txt  op x y z out
      reduce (x is 64 bytes, y and z are -), muladd ((x y + z) mod L),
      canonical (x, then 01 when x < L, else 00).
  curve25519-points.txt  op x y z out
      base ([x]B), double ([x]Y + [z]B, Y an encoded point), decode
      (x an encoding; out 01 when RFC 8032 5.1.3 accepts it, else 00),
      comb (x the entry number 0..15; out the encoding of that entry of
      the fixed-base comb table).
"""
import argparse

from curve25519_util import (BASE, L, P, det_bytes, det_int, from_le, le,
                             pt_add, pt_decode, pt_encode, pt_mul, write)

MASK255 = (1 << 255) - 1


def field_edges():
    vals = [0, 1, 2, 19, P - 2, P - 1, P, P + 1, P + 18, MASK255, 2**254,
            2**255 - 20, 2**26 - 1, 2**26, 2**51, (P - 1) // 2, (P + 1) // 2]
    return [le(v) for v in vals] + [le(v | (1 << 255)) for v in (1, P - 1, 12345)]


def fval(b):
    return (from_le(b) & MASK255) % P


def field_lines(seed, count):
    xs = field_edges() + [det_bytes(f"{seed}:field:{i}", 32) for i in range(count)]
    ys = list(reversed(xs))
    lines = []
    for a, b in zip(xs, ys):
        x, y = fval(a), fval(b)
        out = {
            "mul": x * y % P,
            "sq": x * x % P,
            "sq2": 2 * x * x % P,
            "mul121666": 121666 * x % P,
            "inv": pow(x, P - 2, P),
            "pow22523": pow(x, (P - 5) // 8, P),
            "neg": -x % P,
            "canon": x,
            "addmul": (x + y) * (x - y) % P,
            "submul": (x - y) * (y - x) % P,
        }
        for op, v in out.items():
            lines.append(f"{op} {a.hex()} {b.hex()} {le(v).hex()}")
        lines.append(f"isneg {a.hex()} {b.hex()} {x & 1:02x}")
        lines.append(f"iszero {a.hex()} {b.hex()} {int(x == 0):02x}")
    return lines


def scalar_lines(seed, count):
    lines = []
    wides = [0, 1, L - 1, L, L + 1, 2 * L, 2**252, 2**253, 2**256 - 1, 2**512 - 1,
             L * L - 1, L * (2**259 - 1), (2**512 - 1) // L * L, (2**512 - 1) // L * L - 1]
    wides += [from_le(det_bytes(f"{seed}:wide:{i}", 64)) for i in range(count)]
    for x in wides:
        lines.append(f"reduce {le(x, 64).hex()} - - {le(x % L).hex()}")
    narrows = [0, 1, L - 1, L, L + 1, 2**253 - 1, 2**255, 2**256 - 1, 2**256 - L]
    narrows += [from_le(det_bytes(f"{seed}:narrow:{i}", 32)) for i in range(count)]
    for i, x in enumerate(narrows):
        y = narrows[(i * 7 + 3) % len(narrows)]
        z = narrows[(i * 5 + 1) % len(narrows)]
        lines.append(f"muladd {le(x).hex()} {le(y).hex()} {le(z).hex()} {le((x * y + z) % L).hex()}")
    for x in narrows + [L - 2, L + 2**128, 2**252 - 1, 2**252]:
        lines.append(f"canonical {le(x).hex()} - - {int(x < L):02x}")
    return lines


def is_neutral(p):
    return p[0] % P == 0 and (p[1] - p[2]) % P == 0


def order8_point():
    """A point of order exactly 8: [L]Q for the first decodable y whose
    torsion component has that order."""
    y = 2
    while True:
        q = pt_decode(le(y))
        if q is not None:
            t = pt_mul(L, q)
            if not is_neutral(pt_mul(4, t)):
                assert is_neutral(pt_mul(8, t))
                return t
        y += 1


def point_lines(seed, count):
    lines = []
    scalars = [0, 1, 2, 7, 8, L - 1, L, L + 1, 2**252, 2**253 - 1, 2**255, 2**256 - 1,
               from_le(bytes([255] * 31 + [127]))]
    scalars += [from_le(det_bytes(f"{seed}:k:{i}", 32)) for i in range(count)]
    for k in scalars:
        lines.append(f"base {le(k).hex()} - - {pt_encode(pt_mul(k % L, BASE)).hex()}")
    # [a]A + [b]B for points A of full, small and mixed order
    torsion = order8_point()
    points = [BASE, (0, 1, 1, 0), torsion, pt_add(BASE, torsion)]
    points += [pt_mul(det_int(f"{seed}:A:{i}", L), BASE) for i in range(count)]
    for i, A in enumerate(points):
        a = det_int(f"{seed}:a:{i}", L) if i >= 2 else [0, L - 1][i]
        b = det_int(f"{seed}:b:{i}", L)
        want = pt_add(pt_mul(a, A), pt_mul(b, BASE))
        lines.append(f"double {le(a).hex()} {pt_encode(A).hex()} {le(b).hex()} {pt_encode(want).hex()}")
    # decoding: valid points, then every way RFC 8032 5.1.3 refuses one
    valid = [pt_encode(p) for p in points]
    valid.append(le(1))                                  # the neutral element
    valid.append(le(P - 1))                              # (0, -1), order 2
    bad = []
    for y in (P, P + 1, P + 18, MASK255):                # y not below p
        bad.append(le(y))
        bad.append(le(y | (1 << 255)))
    bad.append(le(1 | (1 << 255)))                       # x = 0 with the sign bit
    bad.append(le((P - 1) | (1 << 255)))
    bad.append(le(2))                                    # y = 2: no x exists
    y = 3
    while len(bad) < 16:                                 # more y with no x
        if pt_decode(le(y)) is None and pt_decode(le(y | (1 << 255))) is None:
            bad.append(le(y | ((y & 1) << 255)))
        y += 1
    for i in range(count):
        e = det_bytes(f"{seed}:enc:{i}", 32)
        (valid if pt_decode(e) is not None else bad).append(e)
    for e in valid:
        assert pt_decode(e) is not None
        lines.append(f"decode {e.hex()} - - 01")
    for e in bad:
        assert pt_decode(e) is None
        lines.append(f"decode {e.hex()} - - 00")
    # the comb table: entry j of the low comb, then of the high comb
    for j in range(16):
        k = 2**96 + sum((1 if (j >> t) & 1 else -1) * 2**(32 * t) for t in range(3))
        if j >= 8:
            k *= 2**128
        lines.append(f"comb {j:02x} - - {pt_encode(pt_mul(k % L, BASE)).hex()}")
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    extract = f"extract: tests/crypto/tools/curve25519_ref.py --seed {args.seed} --count {args.count}"
    src = "source: Python integers, the reference model in tests/crypto/tools/curve25519_util.py"
    nod = "sha256: - (generated, not downloaded)"
    write("curve25519-field.txt", [src, nod, extract, "fields: op a b out"],
          field_lines(args.seed, args.count))
    write("curve25519-scalar.txt", [src, nod, extract, "fields: op x y z out"],
          scalar_lines(args.seed, args.count))
    write("curve25519-points.txt", [src, nod, extract, "fields: op x y z out"],
          point_lines(args.seed, args.count))


if __name__ == "__main__":
    main()
