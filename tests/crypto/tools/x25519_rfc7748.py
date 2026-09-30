"""The X25519 known answers of RFC 7748.

    python3 tests/crypto/tools/x25519_rfc7748.py

Writes tests/crypto/vectors/x25519-rfc7748.txt from the RFC's text:
the two section 5.2 function vectors (`mult k u out`), the iterated
vectors after 1 and 1,000 iterations (`iter n out`), and the section
6.1 Diffie-Hellman example (`dh a pubA b pubB shared`). The
1,000,000-iteration answer goes to x25519-rfc7748-slow.txt, which only
the slow test reads. Every answer is also recomputed with the
reference model in curve25519_util.py, and the script stops if the RFC
and the model disagree.
"""
import re
import sys

from curve25519_util import fetch, write, x25519

URL = "https://www.rfc-editor.org/rfc/rfc7748.txt"
SHA256 = "279ca0ecc5e92e2962e27b846986aeb74729d9dd34bd4a04a362f80dcb596ad3"


def main():
    text = fetch(URL, SHA256).decode("ascii")
    # Section 5.2 up to the X448 vectors: the two X25519 triples.
    s52 = text[text.index("\n5.2.  Test Vectors\n"):]
    x25519_part = s52[:s52.index("X448:")]
    hex64 = r"\s+([0-9a-f]{64})\s"
    triples = re.findall(
        r"Input scalar:" + hex64 + r".*?Input u-coordinate:" + hex64 + r".*?Output u-coordinate:" + hex64,
        x25519_part, re.S)
    if len(triples) != 2:
        sys.exit(f"expected 2 X25519 function vectors, found {len(triples)}")
    iters_part = s52[s52.index("For each iteration"):]
    iters_part = iters_part[iters_part.index("X25519:"):iters_part.index("X448:", iters_part.index("X25519:"))]
    one = re.search(r"After one iteration:" + hex64, iters_part).group(1)
    thousand = re.search(r"After 1,000 iterations:" + hex64, iters_part).group(1)
    s61 = text[text.index("\n6.1.  Curve25519\n"):text.index("\n6.2.  Curve448\n")]
    names = ["Alice's private key, a:", r"Alice's public key, X25519\(a, 9\):",
             "Bob's private key, b:", r"Bob's public key, X25519\(b, 9\):",
             "Their shared secret, K:"]
    dh = [re.search(n + hex64, s61).group(1) for n in names]

    # The model has to agree with every answer before it is written.
    b = bytes.fromhex
    for k, u, out in triples:
        assert x25519(b(k), b(u)) == b(out), "section 5.2 function vector"
    k = u = b("09" + "00" * 31)
    for i in range(1000):
        k, u = x25519(k, u), k
        if i == 0:
            assert k == b(one), "one iteration"
    assert k == b(thousand), "1,000 iterations"
    nine = b("09" + "00" * 31)
    a, pa, bb, pb, shared = (b(x) for x in dh)
    assert x25519(a, nine) == pa and x25519(bb, nine) == pb
    assert x25519(a, pb) == shared and x25519(bb, pa) == shared

    lines = [f"mult {k} {u} {out}" for k, u, out in triples]
    lines += [f"iter 1 {one}", f"iter 1000 {thousand}"]
    lines += ["dh " + " ".join(dh)]
    write("x25519-rfc7748.txt", [
        f"source: RFC 7748 sections 5.2 and 6.1, {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/x25519_rfc7748.py",
        "selection: every X25519 vector except the 1,000,000-iteration one",
        "fields: mult k u out | iter n out | dh a pubA b pubB shared",
    ], lines)


if __name__ == "__main__":
    main()
