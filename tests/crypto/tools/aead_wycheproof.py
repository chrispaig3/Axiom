"""Wycheproof's AES-GCM and ChaCha20-Poly1305 vectors.

    python3 tests/crypto/tools/aead_wycheproof.py

Writes tests/crypto/vectors/wycheproof-aes-gcm.txt and
wycheproof-chacha20-poly1305.txt from testvectors_v1/aes_gcm_test.json
and chacha20_poly1305_test.json at a pinned commit: every test of every
group. Fields: tcId result key iv aad msg ct tag, `result` being
Wycheproof's (valid or invalid; neither file has an acceptable case).
The ChaCha20-Poly1305 cases with a nonce of the wrong size carry no
tag, and their tag field is `-`.

The tests decide what to expect from the lengths: a case whose IV is
not 12 bytes, whose tag is not 16 bytes or (for AES-GCM) whose key is
192 bits uses a parameter the suite does not offer, and the test
checks that it is refused with an error rather than run.
"""
import json
import sys

from aead_util import fetch, write

COMMIT = "3fa63dd0344abb611f1fb1d77e119938603ea230"
BASE = f"https://raw.githubusercontent.com/C2SP/wycheproof/{COMMIT}/testvectors_v1/"
FILES = [
    ("aes_gcm_test.json", "985e5ecc172e181eaf49e89508b9470dcf478002eb7e8559c707eb42dc97dfe7",
     "wycheproof-aes-gcm.txt", "AES-GCM"),
    ("chacha20_poly1305_test.json", "fe61d25f90e1bde4461d00eafe61049e5f29bd999f36b766df9cda90906ad53d",
     "wycheproof-chacha20-poly1305.txt", "CHACHA20-POLY1305"),
]


def h(v):
    return v if v else "-"


def main():
    for (src, sha, out, alg) in FILES:
        url = BASE + src
        data = json.loads(fetch(url, sha))
        if data["algorithm"] != alg:
            sys.exit(f"{src}: algorithm {data['algorithm']}")
        lines = []
        for g in data["testGroups"]:
            if g["type"] != "AeadTest":
                sys.exit(f"{src}: unexpected group type {g['type']}")
            for t in g["tests"]:
                if t["result"] not in ("valid", "invalid"):
                    sys.exit(f"{src} tcId {t['tcId']}: result {t['result']}")
                if len(t["key"]) * 4 != g["keySize"] or len(t["iv"]) * 4 != g["ivSize"] \
                        or len(t["tag"]) * 4 not in (g["tagSize"], 0):
                    sys.exit(f"{src} tcId {t['tcId']}: lengths disagree with the group")
                lines.append(" ".join([str(t["tcId"]), t["result"], h(t["key"]), h(t["iv"]),
                                       h(t["aad"]), h(t["msg"]), h(t["ct"]), h(t["tag"])]))
        if len(lines) != data["numberOfTests"]:
            sys.exit(f"{src}: {len(lines)} tests read, the file says {data['numberOfTests']}")
        write(out, [
            f"source: {url}",
            f"sha256: {sha}",
            "extract: tests/crypto/tools/aead_wycheproof.py",
            "selection: every test of every group; parameters the suite does not offer are expected to be refused",
            "fields: tcId result key iv aad msg ct tag",
        ], lines)


if __name__ == "__main__":
    main()
