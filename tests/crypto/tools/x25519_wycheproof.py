"""Wycheproof's X25519 vectors.

    python3 tests/crypto/tools/x25519_wycheproof.py

Writes tests/crypto/vectors/wycheproof-x25519.txt from
testvectors_v1/x25519_test.json at a pinned commit: every test of
every group, fields tcId result flags private public shared. `result`
is Wycheproof's (valid or acceptable; the file has no invalid X25519
case), `flags` its flag names joined with commas. Every expected
answer is recomputed with the reference model in curve25519_util.py
before it is written.
"""
import json
import sys

from curve25519_util import fetch, write, x25519

COMMIT = "3fa63dd0344abb611f1fb1d77e119938603ea230"
URL = f"https://raw.githubusercontent.com/C2SP/wycheproof/{COMMIT}/testvectors_v1/x25519_test.json"
SHA256 = "35c3f5231cf25cc640b524d403461deee9e49441d5d915a3a25b2c8ff5adbe7d"


def main():
    data = json.loads(fetch(URL, SHA256))
    lines = []
    for group in data["testGroups"]:
        if group["type"] != "XdhComp" or group["curve"] != "curve25519":
            sys.exit(f"unexpected group {group['type']} {group.get('curve')}")
        for t in group["tests"]:
            priv, pub, shared = t["private"], t["public"], t["shared"]
            if t["result"] not in ("valid", "acceptable"):
                sys.exit(f"tcId {t['tcId']}: unexpected result {t['result']}")
            if x25519(bytes.fromhex(priv), bytes.fromhex(pub)).hex() != shared:
                sys.exit(f"tcId {t['tcId']}: the reference model disagrees")
            flags = ",".join(t["flags"]) or "-"
            lines.append(f"{t['tcId']} {t['result']} {flags} {priv} {pub} {shared}")
    if len(lines) != data["numberOfTests"]:
        sys.exit(f"{len(lines)} tests read, the file says {data['numberOfTests']}")
    write("wycheproof-x25519.txt", [
        f"source: {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/x25519_wycheproof.py",
        "fields: tcId result flags private public shared",
    ], lines)


if __name__ == "__main__":
    main()
