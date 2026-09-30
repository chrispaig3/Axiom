#!/usr/bin/env python3
"""Write the Float module's known-answer inputs.

    python3 tests/stdlib/tools/float_vectors.py

tests/stdlib/690-float-repr.in: one finite binary64 per line, as
"<bits> <repr>", where <bits> is its encoding as a signed 64-bit integer
and <repr> is Python's repr of it (the shortest string that reads back).

tests/stdlib/691-float-parse.in: one decimal per line, as
"<text> <bits>", where <bits> is the binary64 Python's float() rounds
<text> to (correctly rounded, ties to even).

Both files are deterministic: the seed is fixed, and Python's repr and
float() are correctly rounded on every platform CPython supports.
"""
import random
import struct
import sys

SEED = 20260930


def to_bits(x):
    return struct.unpack("<q", struct.pack("<d", x))[0]


def from_bits(b):
    return struct.unpack("<d", struct.pack("<q", b))[0]


def finite(b):
    return (b >> 52) & 2047 != 2047


def exact_decimal(m, e):
    """The exact decimal text of m * 2**e, for integers m >= 0."""
    if e >= 0:
        return str(m << e)
    digits = str(m * 5 ** (-e))
    point = len(digits) + e
    if point <= 0:
        return "0." + "0" * (-point) + digits
    return digits[:point] + "." + digits[point:]


def repr_cases(rng):
    out = []
    # Every sign, exponent and significand pattern, uniformly.
    for _ in range(6000):
        b = rng.getrandbits(64) - (1 << 63)
        if finite(b):
            out.append(b)
    # Values people write: short decimals at every scale.
    for _ in range(3000):
        digits = rng.randint(1, 17)
        mant = rng.randrange(10 ** (digits - 1), 10 ** digits)
        x = float(f"{mant}e{rng.randint(-330, 310)}")
        out.append(to_bits(x if rng.random() < 0.5 else -x))
    # Boundaries: powers of two and ten and their neighbours, subnormals,
    # the extremes, integers near 2^53.
    specials = [0.0, -0.0, 5e-324, 1.7976931348623157e308, 2.2250738585072014e-308,
                2.225073858507201e-308, 9007199254740992.0, 9007199254740993.0, 0.1, 0.2, 0.3]
    for k in range(-1074, 1024):
        specials.append(2.0 ** k)
    for k in range(-323, 309):
        specials.append(float(f"1e{k}"))
    for s in specials:
        b = to_bits(s)
        for d in (-1, 0, 1):
            if finite(b + d) and (b + d) >> 63 == b >> 63:
                out.append(b + d)
    return out


def parse_cases(rng):
    out = []
    # Random digit strings, point anywhere, exponents past both ends.
    for _ in range(5000):
        n = rng.randint(1, 40)
        digits = "".join(rng.choice("0123456789") for _ in range(n))
        point = rng.randint(0, n)
        text = digits[:point] + ("." + digits[point:] if point < n else "")
        if rng.random() < 0.7:
            text += rng.choice("eE") + rng.choice(["", "+", "-"]) + str(rng.randint(0, 350))
        if text.startswith("."):
            text = "0" + text
        if rng.random() < 0.3:
            text = "-" + text
        out.append(text)
    # Exact halfway points between neighbouring floats, and a hair either
    # side of them: the cases a parser that rounds twice gets wrong.
    for _ in range(500):
        b = rng.randrange(1, (2047 << 52) - 1)
        m = (b & ((1 << 52) - 1)) | ((1 << 52) if b >> 52 else 0)
        e = (b >> 52) - 1075 if b >> 52 else -1074
        half = exact_decimal(2 * m + 1, e - 1)
        out.append(half)
        out.append(half + "000000000000000000001")
        if "." in half and half.rstrip("0") != half.split(".")[0] + ".":
            cut = half[:-1] if half[-1] != "." else half
            out.append(cut)
    # Long inputs: more than 800 significant digits.
    for _ in range(20):
        n = rng.randint(801, 1200)
        digits = str(rng.randint(1, 9)) + "".join(rng.choice("0123456789") for _ in range(n - 1))
        out.append(digits[:1] + "." + digits[1:] + "e" + str(rng.randint(-320, 300)))
    return out


def main():
    rng = random.Random(SEED)
    with open("tests/stdlib/690-float-repr.in", "w") as f:
        for b in repr_cases(rng):
            f.write(f"{b} {repr(from_bits(b))}\n")
    with open("tests/stdlib/691-float-parse.in", "w") as f:
        for text in parse_cases(rng):
            f.write(f"{text} {to_bits(float(text))}\n")


if __name__ == "__main__":
    sys.exit(main())
