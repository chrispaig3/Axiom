"""Extract Wycheproof's HMAC-SHA-256 and HMAC-SHA-512 tests into
tests/crypto/vectors/wycheproof-hmac-sha256.txt and
wycheproof-hmac-sha512.txt.

    python3 tests/crypto/tools/hmac_wycheproof.py

Every test of testvectors_v1/hmac_sha{256,512}_test.json at a pinned
commit of github.com/C2SP/wycheproof. Fields: tagbits result key msg
tag, where `result` is valid or invalid and a tag shorter than the
hash's output is the full tag's prefix.
"""
import json

from hashfam_util import fetch, hx, write

COMMIT = "3fa63dd0344abb611f1fb1d77e119938603ea230"
BASE = f"https://raw.githubusercontent.com/C2SP/wycheproof/{COMMIT}/testvectors_v1"
FILES = {
    "256": ("hmac_sha256_test.json", "2d201cfa61d1bf95e6f5d07d96634b4a348b31e8eaa277ad7c8d09677b7a743f"),
    "512": ("hmac_sha512_test.json", "b6c90477bdb4a6fc8ee3d1f7b2c0b69a8dfffab34718abaa6cabd71cc2ba1207"),
}


def main():
    for alg, (name, sha) in FILES.items():
        url = f"{BASE}/{name}"
        doc = json.loads(fetch(url, sha))
        lines = []
        for g in doc["testGroups"]:
            for t in g["tests"]:
                assert t["result"] in ("valid", "invalid")
                lines.append(f"{g['tagSize']} {t['result']} {hx(bytes.fromhex(t['key']))} "
                             f"{hx(bytes.fromhex(t['msg']))} {hx(bytes.fromhex(t['tag']))}")
        assert len(lines) == doc["numberOfTests"]
        write(f"wycheproof-hmac-sha{alg}.txt", [
            f"source: {url}",
            f"sha256: {sha}",
            "extract: tests/crypto/tools/hmac_wycheproof.py",
            "selection: every test",
            "fields: tagbits result key msg tag",
        ], lines)


if __name__ == "__main__":
    main()
