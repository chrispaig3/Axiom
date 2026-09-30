"""Ed25519 negative and edge-case vectors: strict decoding of public
keys and signatures, and how verification treats keys and R of small
order.

    python3 tests/crypto/tools/ed25519_strict.py --seed ed25519-strict-1 --count 16

Writes tests/crypto/vectors/ed25519-strict.txt, fields: op a b c want,
`want` 01 for accepted and 00 for refused:

  pk a - - want       a 32-byte public key: refused when y is not
                      below p, when no x exists, or when x = 0 carries
                      the sign bit (RFC 8032 5.1.3)
  sig a - - want      a 64-byte signature: refused when R is refused as
                      above or when S is not below L (5.1.7)
  verify a b c want   public key a, message b, signature c, and the
                      verdict of the cofactorless equation with strict
                      decoding. The keys include the eight points of
                      small order and keys with a small-order component
                      added; signatures under them are built to satisfy
                      the equation where that is possible without a
                      secret, and the verdict says whether they do.

Verdicts come from the reference model in curve25519_util.py.
"""
import argparse

from curve25519_util import (BASE, L, P, det_bytes, det_int, ed25519_expand,
                             ed25519_public, ed25519_sign, ed25519_verify, le,
                             pt_add, pt_decode, pt_encode, pt_mul, sha512_modL,
                             write)

MASK255 = (1 << 255) - 1


def small_order_points():
    """The eight points whose order divides 8, from the torsion part
    of decodable points."""
    found = {}
    y = 2
    while len(found) < 8:
        q = pt_decode(le(y))
        if q is not None:
            t = pt_mul(L, q)
            for k in range(8):
                e = pt_encode(pt_mul(k, t))
                found[e] = pt_mul(k, t)
        y += 1
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True)
    ap.add_argument("--count", type=int, required=True)
    args = ap.parse_args()
    seed = args.seed
    lines = []

    # public keys
    good = [ed25519_public(det_bytes(f"{seed}:key:{i}", 32)) for i in range(args.count)]
    small = small_order_points()
    good += sorted(small)
    bad = []
    for y in (P, P + 1, P + 2, P + 18, MASK255):
        bad += [le(y), le(y | (1 << 255))]
    bad += [le(1 | (1 << 255)), le((P - 1) | (1 << 255))]   # x = 0 with the sign bit
    y = 2
    while len(bad) < 12 + args.count:
        if pt_decode(le(y)) is None and pt_decode(le(y | (1 << 255))) is None:
            bad.append(le(y | ((y & 1) << 255)))
        y += 1
    for e in good:
        assert pt_decode(e) is not None
        lines.append(f"pk {e.hex()} - - 01")
    for e in bad:
        assert pt_decode(e) is None
        lines.append(f"pk {e.hex()} - - 00")

    # signatures: a valid one, then R or S spoiled
    sd = det_bytes(f"{seed}:sigkey", 32)
    msg = b"strict"
    sig = ed25519_sign(sd, msg)
    r, s = sig[:32], int.from_bytes(sig[32:], "little")
    sigs = [(sig, True)]
    for bad_s in (L, L + 1, L + s, 2**252 + 2**251, 2**253 - 1, 2**256 - 1):
        sigs.append((r + le(bad_s), False))
    sigs.append((r + le(L - 1), True))
    sigs.append((r + le(0), True))
    for e in bad[:6]:
        sigs.append((e + sig[32:], False))
    for sgn, ok in sigs:
        lines.append(f"sig {sgn.hex()} - - {'01' if ok else '00'}")

    # verification under keys of small and mixed order
    cases = []
    for enc, T in sorted(small.items()):
        # R = [S]B satisfies the equation exactly when [k]T is neutral
        for j in range(3):
            S = det_int(f"{seed}:S:{enc.hex()}:{j}", L)
            R = pt_encode(pt_mul(S, BASE))
            m = det_bytes(f"{seed}:m:{enc.hex()}:{j}", 8)
            cases.append((enc, m, R + le(S)))
        # R neutral, S = 0: [0]B = O + [k]T holds when k T is neutral
        for j in range(2):
            m = det_bytes(f"{seed}:m0:{enc.hex()}:{j}", 8)
            cases.append((enc, m, le(1) + le(0)))
    for i in range(4):
        # an honest key with an order-8 point added: signatures by the
        # honest secret verify only when k is a multiple of 8
        sd = det_bytes(f"{seed}:mixed:{i}", 32)
        T = small[sorted(small)[i + 1]]
        a0 = pt_decode(ed25519_public(sd))
        mixed = pt_encode(pt_add(a0, T))
        a, prefix = ed25519_expand(sd)
        for j in range(4):
            m = det_bytes(f"{seed}:mm:{i}:{j}", 8)
            rr = sha512_modL(prefix, m)
            R = pt_encode(pt_mul(rr, BASE))
            k = sha512_modL(R, mixed, m)
            cases.append((mixed, m, R + le((rr + k * a) % L)))
    for pk, m, sgn in cases:
        v = ed25519_verify(pk, m, sgn)
        lines.append(f"verify {pk.hex()} {m.hex()} {sgn.hex()} {'01' if v else '00'}")

    write("ed25519-strict.txt", [
        "source: the reference model in tests/crypto/tools/curve25519_util.py (RFC 8032 5.1.3 and 5.1.7)",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/ed25519_strict.py --seed {args.seed} --count {args.count}",
        "fields: op a b c want",
    ], lines)


if __name__ == "__main__":
    main()
