"""Extract Wycheproof's HKDF-SHA-256 and HKDF-SHA-512 tests into
tests/crypto/vectors/wycheproof-hkdf-sha256.txt and
wycheproof-hkdf-sha512.txt.

    python3 tests/crypto/tools/hkdf_wycheproof.py

Every test of testvectors_v1/hkdf_sha{256,512}_test.json at a pinned
commit of github.com/C2SP/wycheproof. Fields: size result ikm salt
info okm, where `result` is valid or invalid; an invalid case asks for
more than 255 blocks of output and has no okm (`-`).
"""
import json

from hashfam_util import fetch, hx, write

COMMIT = "3fa63dd0344abb611f1fb1d77e119938603ea230"
BASE = f"https://raw.githubusercontent.com/C2SP/wycheproof/{COMMIT}/testvectors_v1"
FILES = {
    "256": ("hkdf_sha256_test.json", "bb2b462a38b251cb52a2aede706d6d4b62b26864f4e80c95497507ddb07c5f1e"),
    "512": ("hkdf_sha512_test.json", "bb9a21f4e86041caf5d7792b030349f8ff289087f195b2fbc0fc0afc39deca6f"),
}


def main():
    for alg, (name, sha) in FILES.items():
        url = f"{BASE}/{name}"
        doc = json.loads(fetch(url, sha))
        lines = []
        for g in doc["testGroups"]:
            for t in g["tests"]:
                assert t["result"] in ("valid", "invalid")
                b = lambda k: hx(bytes.fromhex(t[k]))
                lines.append(f"{t['size']} {t['result']} {b('ikm')} {b('salt')} {b('info')} {b('okm')}")
        assert len(lines) == doc["numberOfTests"]
        write(f"wycheproof-hkdf-sha{alg}.txt", [
            f"source: {url}",
            f"sha256: {sha}",
            "extract: tests/crypto/tools/hkdf_wycheproof.py",
            "selection: every test",
            "fields: size result ikm salt info okm",
        ], lines)


if __name__ == "__main__":
    main()
