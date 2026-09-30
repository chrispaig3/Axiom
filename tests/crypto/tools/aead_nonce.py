"""Expected nonces for Crypto.Aead's NonceSequence.

    python3 tests/crypto/tools/aead_nonce.py

Writes tests/crypto/vectors/aead-nonce.txt. A sequence is the
deterministic construction of SP 800-38D 8.2.1: a 4-byte fixed field
(the prefix) followed by a 64-bit big-endian invocation counter. Each
case resumes a sequence at `start`, draws `steps` nonces, and records
the counter position that follows and the last nonce drawn. Prefixes
and starts are drawn deterministically from SHAKE256, plus the edges:
counter 0, the carry across each byte, and the last usable counter,
2^63 - 2.

Fields: prefix start steps position nonce.
"""
from aead_util import det_bytes, det_int, hx, write

SEED = "aead-nonce-1"
LAST = 2**63 - 2


def main():
    cases = [
        (bytes(4), 0, 1), (b"\x01\x02\x03\x04", 0, 3), (b"\xff\xff\xff\xff", 255, 2),
        (b"\x00\x00\x00\x07", 65535, 2), (b"\x80\x00\x00\x00", 2**32 - 1, 2),
        (b"\x12\x34\x56\x78", 2**56 - 1, 2), (b"\xa1\xb2\xc3\xd4", LAST, 1),
        (b"\xa1\xb2\xc3\xd4", LAST - 5, 6),
    ]
    for i in range(24):
        lab = f"{SEED}/{i}"
        start = int.from_bytes(det_bytes(f"{lab}/start", 8), "big") >> 1
        start = min(start, LAST - 40)
        cases.append((det_bytes(f"{lab}/prefix", 4), start, 1 + det_int(f"{lab}/steps", 40)))
    lines = []
    for (prefix, start, steps) in cases:
        last = start + steps - 1
        assert last <= LAST
        nonce = prefix + last.to_bytes(8, "big")
        lines.append(f"{hx(prefix)} {start} {steps} {last + 1} {hx(nonce)}")
    write("aead-nonce.txt", [
        "source: SP 800-38D section 8.2.1 (deterministic construction), computed",
        "sha256: - (generated, not downloaded)",
        f"extract: tests/crypto/tools/aead_nonce.py (seed {SEED})",
        "fields: prefix start steps position nonce",
    ], lines)


if __name__ == "__main__":
    main()
