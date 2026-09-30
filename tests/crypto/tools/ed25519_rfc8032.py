"""The Ed25519 known answers of RFC 8032, section 7.1.

    python3 tests/crypto/tools/ed25519_rfc8032.py

Writes tests/crypto/vectors/ed25519-rfc8032.txt from the RFC's text,
fields: name secret public message signature, one line for each of
the five tests (TEST 1, 2, 3, 1024 and SHA(abc)). The hex of each field
is gathered across the page breaks of the text, its length checked
against the one the RFC states, and every signature recomputed with
the reference model in curve25519_util.py before it is written.
"""
import re
import sys

from curve25519_util import ed25519_public, ed25519_sign, ed25519_verify, fetch, hx, write

URL = "https://www.rfc-editor.org/rfc/rfc8032.txt"
SHA256 = "ed63657ff389301282b169b0abde9b5dd2c7e4d524fdfa5da6ff3094fc93c4c3"


def field(block, label, nxt):
    """The hex under `label`, up to the label `nxt`: every line that is
    only hex digits, so page headers and footers drop out."""
    start = block.index(label) + len(label)
    end = block.index(nxt, start) if nxt else len(block)
    hexlines = [ln.strip() for ln in block[start:end].splitlines()
                if re.fullmatch(r"\s*[0-9a-f]+\s*", ln)]
    return bytes.fromhex("".join(hexlines))


def main():
    text = fetch(URL, SHA256).decode("ascii")
    sec = text[text.index("\n7.1.  Test Vectors for Ed25519\n"):text.index("\n7.2.  Test Vectors for Ed25519ctx\n")]
    blocks = sec.split("-----TEST ")[1:]
    if len(blocks) != 5:
        sys.exit(f"expected 5 tests in section 7.1, found {len(blocks)}")
    lines = []
    for block in blocks:
        name = block.split()[0]
        m = re.search(r"MESSAGE \(length (\d+) bytes?\):", block)
        msg_label, msg_len = m.group(0), int(m.group(1))
        secret = field(block, "SECRET KEY:", "PUBLIC KEY:")
        public = field(block, "PUBLIC KEY:", msg_label)
        message = field(block, msg_label, "SIGNATURE:")
        signature = field(block, "SIGNATURE:", "-----" if "-----" in block else None)
        if (len(secret), len(public), len(message), len(signature)) != (32, 32, msg_len, 64):
            sys.exit(f"TEST {name}: field lengths {len(secret)} {len(public)} {len(message)} {len(signature)}")
        if ed25519_public(secret) != public or ed25519_sign(secret, message) != signature \
                or not ed25519_verify(public, message, signature):
            sys.exit(f"TEST {name}: the reference model disagrees")
        lines.append(f"{name} {secret.hex()} {public.hex()} {hx(message)} {signature.hex()}")
    write("ed25519-rfc8032.txt", [
        f"source: RFC 8032 section 7.1, {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/ed25519_rfc8032.py",
        "fields: name secret public message signature",
    ], lines)


if __name__ == "__main__":
    main()
