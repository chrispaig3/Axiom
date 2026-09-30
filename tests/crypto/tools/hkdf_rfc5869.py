"""Extract RFC 5869 Appendix A's HKDF-SHA-256 test cases (A.1 to A.3)
into tests/crypto/vectors/hkdf-rfc5869.txt. Cases A.4 to A.7 are
HKDF-SHA-1, which this suite does not implement.

    python3 tests/crypto/tools/hkdf_rfc5869.py

Fields: ikm salt info len prk okm.
"""
import re

from hashfam_util import fetch, hx, rfc_fields, write

URL = "https://www.rfc-editor.org/rfc/rfc5869.txt"
SHA256 = "7a40eb3835b35fc947eb12a2ed614db079d43b26e50dbc537c31fba16397089c"


def main():
    text = fetch(URL, SHA256).decode("ascii")
    body = text[text.index("\nA.1.  Test Case 1\n") + 1:text.index("\nA.4.  Test Case 4\n")]
    cases = re.split(r"\nA\.\d\.  Test Case \d\n", "\n" + body)[1:]
    lines = []
    for case in cases:
        assert "Hash = SHA-256" in case
        f = dict(rfc_fields(case, ["IKM", "salt", "info", "PRK", "OKM"]))
        n = int(re.search(r"L    = (\d+)", case).group(1))
        salt = f.get("salt", b"")
        info = f.get("info", b"")
        assert len(f["OKM"]) == n
        lines.append(f"{hx(f['IKM'])} {hx(salt)} {hx(info)} {n} {f['PRK'].hex()} {f['OKM'].hex()}")
    assert len(lines) == 3
    write("hkdf-rfc5869.txt", [
        f"source: {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/hkdf_rfc5869.py",
        "selection: Appendix A.1 to A.3 (SHA-256); an empty salt or info is written -",
        "fields: ikm salt info len prk okm",
    ], lines)


if __name__ == "__main__":
    main()
