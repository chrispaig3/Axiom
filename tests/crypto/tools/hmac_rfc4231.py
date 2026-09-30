"""Extract RFC 4231's HMAC-SHA-256 and HMAC-SHA-512 test cases into
tests/crypto/vectors/hmac-rfc4231.txt.

    python3 tests/crypto/tools/hmac_rfc4231.py

Fields: alg key msg tag, `alg` 256 or 512. Test case 5's tags are the
RFC's, truncated to 128 bits; a tag shorter than the hash's output is
compared with the full tag's prefix.
"""
import re

from hashfam_util import fetch, hx, rfc_fields, write

URL = "https://www.rfc-editor.org/rfc/rfc4231.txt"
SHA256 = "72178527ce93500e730bc8eb182b857e583096d652b64ece0879c52ba1df973b"


def main():
    text = fetch(URL, SHA256).decode("ascii")
    body = text[text.index("\n4.2.  Test Case 1\n") + 1:text.index("\n5.  Security Considerations\n")]
    cases = re.split(r"\n4\.\d+\.  Test Case \d+\n", "\n" + body)[1:]
    lines = []
    for case in cases:
        f = dict(rfc_fields(case, ["Key", "Data", "HMAC-SHA-224", "HMAC-SHA-256", "HMAC-SHA-384", "HMAC-SHA-512"]))
        for alg in ("256", "512"):
            lines.append(f"{alg} {hx(f['Key'])} {hx(f['Data'])} {f['HMAC-SHA-' + alg].hex()}")
    assert len(lines) == 14, len(lines)
    write("hmac-rfc4231.txt", [
        f"source: {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/hmac_rfc4231.py",
        "selection: test cases 1 to 7, the HMAC-SHA-256 and HMAC-SHA-512 values",
        "fields: alg key msg tag",
    ], lines)


if __name__ == "__main__":
    main()
