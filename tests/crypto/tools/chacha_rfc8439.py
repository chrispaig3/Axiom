"""RFC 8439's ChaCha20, Poly1305 and ChaCha20-Poly1305 examples.

    python3 tests/crypto/tools/chacha_rfc8439.py

Reads the RFC's text and writes three vector files from its worked
examples (section 2) and its test vectors (Appendix A):

- chacha20-rfc8439.txt: id key nonce counter plaintext ciphertext.
  The block-function vectors (2.3.2, A.1) are written as the
  encryption of 64 zero bytes, whose ciphertext is the keystream
  block; the Poly1305 key-generation vectors (2.6.2, A.4) as the
  encryption of 32 zero bytes from counter 0; 2.4.2 and A.2 as given.
- poly1305-rfc8439.txt: id key msg tag (2.5.2, A.3 #1-#11; for #5 to
  #11 the key is R || S).
- chacha20-poly1305-rfc8439.txt: id key nonce aad plaintext
  ciphertext tag (2.8.2, whose nonce is the 32-bit fixed part followed
  by the 64-bit IV, and A.5).

Every hex dump is read from the text, not retyped.
"""
import re
import sys

from aead_util import fetch, hx, write

URL = "https://www.rfc-editor.org/rfc/rfc8439.txt"
SHA256 = "25bef70fbf7a07ff45c2fe4cb7c6ce954eac687413d8610603268b4e4415324c"


def page_clean(text):
    """The RFC's lines without page footers, headers and form feeds."""
    out = []
    for line in text.split("\n"):
        line = line.replace("\f", "")
        if line.startswith("Nir & Langley") or line.startswith("RFC 8439   "):
            continue
        out.append(line)
    return out


class Doc:
    def __init__(self, lines):
        self.lines = lines

    def find(self, pattern, start, end=None):
        """The index of the first line at or after `start` (and before
        `end`) whose text matches `pattern`."""
        end = len(self.lines) if end is None else end
        for i in range(start, end):
            if re.search(pattern, self.lines[i]):
                return i
        sys.exit(f"not found after line {start}: {pattern!r}")

    def dump(self, label, start, end=None):
        """The bytes of the offset-prefixed hex dump after the line
        matching `label`: '000  xx xx ...  ascii'."""
        i = self.find(label, start, end) + 1
        out = bytearray()
        seen = False
        while i < len(self.lines):
            line = self.lines[i]
            m = re.match(r"^\s*(\d{3})  ", line)
            if m:
                if int(m.group(1)) != len(out):
                    sys.exit(f"line {i}: offset {m.group(1)} after {len(out)} bytes")
                for tok in line[m.end():m.end() + 48].split():
                    if not re.fullmatch(r"[0-9a-f]{2}", tok):
                        sys.exit(f"line {i}: bad hex byte {tok!r}")
                    out.append(int(tok, 16))
                seen = True
            elif line.strip() and seen:
                break
            elif line.strip() and not seen:
                sys.exit(f"line {i}: expected a hex dump after {label!r}")
            i += 1
        return bytes(out)

    def rows(self, label, start, end=None):
        """The bytes of the plain rows 'XX XX ... XX' after the line
        matching `label` (Appendix A.3's #5 to #11)."""
        i = self.find(label, start, end) + 1
        out = bytearray()
        while i < len(self.lines):
            line = self.lines[i].strip()
            if re.fullmatch(r"([0-9A-F]{2} )*[0-9A-F]{2}", line):
                out += bytes.fromhex(line)
            elif line or out:
                break
            i += 1
        return bytes(out)

    def colons(self, label, start, end=None):
        """The bytes of a colon-separated list after `label`, which may
        start on the next line and run on over several: a list that
        ends in ':' or in half a byte continues on the next line, and
        prose after the list is ignored."""
        i = self.find(label, start, end)
        line = self.lines[i]
        text = re.match(r"[\s(]*([0-9a-f:]*)", line[re.search(label, line).end():]).group(1)
        j = i + 1
        while text == "" or text.endswith(":") or len(text.split(":")[-1]) == 1:
            m = re.match(r"\s*\(?([0-9a-f:]+)", self.lines[j])
            if not m:
                sys.exit(f"line {j}: a colon list after {label!r} stops early")
            text += m.group(1)
            j += 1
        return bytes(int(b, 16) for b in text.split(":"))

    def number(self, label, start, end=None):
        i = self.find(label, start, end)
        return int(re.search(label + r"\s*(\d+)", self.lines[i]).group(1))


def main():
    d = Doc(page_clean(fetch(URL, SHA256).decode("ascii")))
    sec = {name: d.find(pat, 0) for name, pat in [
        ("2.3.2", r"^2\.3\.2\.  "), ("2.4", r"^2\.4\.  "), ("2.4.2", r"^2\.4\.2\.  "),
        ("2.5", r"^2\.5\.  "), ("2.5.2", r"^2\.5\.2\.  "), ("2.6", r"^2\.6\.  "),
        ("2.6.2", r"^2\.6\.2\.  "), ("2.7", r"^2\.7\.  "), ("2.8.2", r"^2\.8\.2\.  "),
        ("3", r"^3\.  "), ("A.1", r"^A\.1\.  "), ("A.2", r"^A\.2\.  "), ("A.3", r"^A\.3\.  "),
        ("A.4", r"^A\.4\.  "), ("A.5", r"^A\.5\.  "), ("B", r"^Appendix B\.  ")]}

    def vectors(a, b):
        """The line ranges of the 'Test Vector #n' blocks between two
        section starts."""
        starts = [i for i in range(sec[a], sec[b]) if re.search(r"Test Vector #\d+", d.lines[i])]
        return [(s, e) for s, e in zip(starts, starts[1:] + [sec[b]])]

    chacha = []
    s, e = sec["2.3.2"], sec["2.4"]
    key = d.colons(r"Key = ", s, e)
    nonce = d.colons(r"Nonce = ", s, e)
    ctr = d.number(r"Block Count =", s, e)
    chacha.append(("2.3.2", key, nonce, ctr, bytes(64), d.dump(r"Serialized Block:", s, e)))
    s, e = sec["2.4.2"], sec["2.5"]
    chacha.append(("2.4.2", d.colons(r"Key = ", s, e), d.colons(r"Nonce = ", s, e),
                   d.number(r"Initial Counter =", s, e), d.dump(r"Plaintext Sunscreen:", s, e),
                   d.dump(r"Ciphertext Sunscreen:", s, e)))
    s, e = sec["2.6.2"], sec["2.7"]
    chacha.append(("2.6.2", d.dump(r"^\s*Key:", s, e), d.dump(r"^\s*Nonce:", s, e), 0, bytes(32),
                   d.dump(r"Output bytes:", s, e)))
    for n, (s, e) in enumerate(vectors("A.1", "A.2"), 1):
        chacha.append((f"A.1#{n}", d.dump(r"^\s*Key:", s, e), d.dump(r"^\s*Nonce:", s, e),
                       d.number(r"Block Counter =", s, e), bytes(64), d.dump(r"Keystream:", s, e)))
    for n, (s, e) in enumerate(vectors("A.2", "A.3"), 1):
        chacha.append((f"A.2#{n}", d.dump(r"^\s*Key:", s, e), d.dump(r"^\s*Nonce:", s, e),
                       d.number(r"Initial Block Counter =", s, e), d.dump(r"Plaintext:", s, e),
                       d.dump(r"Ciphertext:", s, e)))
    for n, (s, e) in enumerate(vectors("A.4", "A.5"), 1):
        chacha.append((f"A.4#{n}", d.dump(r"The ChaCha20 Key", s, e), d.dump(r"The nonce:", s, e), 0,
                       bytes(32), d.dump(r"Poly1305 one-time key:", s, e)))
    for (cid, key, nonce, ctr, pt, ct) in chacha:
        if len(key) != 32 or len(nonce) != 12 or len(pt) != len(ct) or not ct:
            sys.exit(f"{cid}: unexpected lengths")

    poly = []
    s, e = sec["2.5.2"], sec["2.6"]
    poly.append(("2.5.2", d.colons(r"Key Material: ", s, e), d.dump(r"Message to be Authenticated:", s, e),
                 d.colons(r"Tag: ", s, e)))
    for n, (s, e) in enumerate(vectors("A.3", "A.4"), 1):
        if n <= 4:
            poly.append((f"A.3#{n}", d.dump(r"One-time Poly1305 Key:", s, e), d.dump(r"Text to MAC:", s, e),
                         d.dump(r"^\s*Tag:", s, e)))
        else:
            poly.append((f"A.3#{n}", d.rows(r"^\s*R:", s, e) + d.rows(r"^\s*S:", s, e),
                         d.rows(r"^\s*data:", s, e), d.rows(r"^\s*tag:", s, e)))
    if len(poly) != 12:
        sys.exit(f"{len(poly)} Poly1305 vectors, expected 12")
    for (cid, key, msg, tag) in poly:
        if len(key) != 32 or len(tag) != 16 or not msg:
            sys.exit(f"{cid}: unexpected lengths")

    aead = []
    s, e = sec["2.8.2"], sec["3"]
    nonce = d.dump(r"32-bit fixed-common part:", s, e) + d.dump(r"^\s*IV:", s, e)
    aead.append(("2.8.2", d.dump(r"^\s*Key:", s, e), nonce, d.dump(r"^\s*AAD:", s, e),
                 d.dump(r"^\s*Plaintext:", s, e), d.dump(r"^\s*Ciphertext:", s, e), d.colons(r"Tag:\s*", s, e)))
    s, e = sec["A.5"], sec["B"]
    aead.append(("A.5", d.dump(r"The ChaCha20 Key", s, e), d.dump(r"The nonce:", s, e),
                 d.dump(r"The AAD:", s, e), d.dump(r"Plaintext::", s, e), d.dump(r"^\s*Ciphertext:", s, e),
                 d.dump(r"Received Tag:", s, e)))
    for (cid, key, nonce, aad, pt, ct, tag) in aead:
        if len(key) != 32 or len(nonce) != 12 or len(pt) != len(ct) or len(tag) != 16:
            sys.exit(f"{cid}: unexpected lengths")

    header = [f"source: {URL}", f"sha256: {SHA256}", "extract: tests/crypto/tools/chacha_rfc8439.py"]
    write("chacha20-rfc8439.txt", header + [
        "selection: 2.3.2, 2.4.2, 2.6.2, A.1 #1-#5, A.2 #1-#3, A.4 #1-#3",
        "fields: id key nonce counter plaintext ciphertext"],
        [f"{c} {hx(k)} {hx(n)} {ctr} {hx(p)} {hx(x)}" for (c, k, n, ctr, p, x) in chacha])
    write("poly1305-rfc8439.txt", header + [
        "selection: 2.5.2, A.3 #1-#11",
        "fields: id key msg tag"],
        [f"{c} {hx(k)} {hx(m)} {hx(t)}" for (c, k, m, t) in poly])
    write("chacha20-poly1305-rfc8439.txt", header + [
        "selection: 2.8.2, A.5",
        "fields: id key nonce aad plaintext ciphertext tag"],
        [f"{c} {hx(k)} {hx(n)} {hx(a)} {hx(p)} {hx(x)} {hx(t)}" for (c, k, n, a, p, x, t) in aead])


if __name__ == "__main__":
    main()
