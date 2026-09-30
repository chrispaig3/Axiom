"""Wycheproof's Ed25519 verification vectors.

    python3 tests/crypto/tools/ed25519_wycheproof.py

Writes tests/crypto/vectors/wycheproof-ed25519.txt from
testvectors_v1/ed25519_test.json at a pinned commit: every test of
every group, fields tcId result flags pk msg sig. `result` is valid or
invalid (the file has no acceptable Ed25519 case), `flags` its flag
names joined with commas, `pk` the group's public key. Every verdict
is recomputed with the reference model in curve25519_util.py (strict
decoding, S below L, the cofactorless equation) before it is written.
"""
import json
import sys

from curve25519_util import ed25519_verify, fetch, hx, write

COMMIT = "3fa63dd0344abb611f1fb1d77e119938603ea230"
URL = f"https://raw.githubusercontent.com/C2SP/wycheproof/{COMMIT}/testvectors_v1/ed25519_test.json"
SHA256 = "752d2ea7d7c6cf4736381b6cbacb61f8182b126ab7cd9b058f00c50084975536"


def main():
    data = json.loads(fetch(URL, SHA256))
    lines = []
    for group in data["testGroups"]:
        if group["type"] != "EddsaVerify" or group["publicKey"]["curve"] != "edwards25519":
            sys.exit(f"unexpected group {group['type']}")
        pk = group["publicKey"]["pk"]
        for t in group["tests"]:
            if t["result"] not in ("valid", "invalid"):
                sys.exit(f"tcId {t['tcId']}: unexpected result {t['result']}")
            want = t["result"] == "valid"
            if ed25519_verify(bytes.fromhex(pk), bytes.fromhex(t["msg"]), bytes.fromhex(t["sig"])) != want:
                sys.exit(f"tcId {t['tcId']}: the reference model disagrees")
            flags = ",".join(t["flags"]) or "-"
            lines.append(f"{t['tcId']} {t['result']} {flags} {pk} {hx(bytes.fromhex(t['msg']))} {hx(bytes.fromhex(t['sig']))}")
    if len(lines) != data["numberOfTests"]:
        sys.exit(f"{len(lines)} tests read, the file says {data['numberOfTests']}")
    write("wycheproof-ed25519.txt", [
        f"source: {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/ed25519_wycheproof.py",
        "fields: tcId result flags pk msg sig",
    ], lines)


if __name__ == "__main__":
    main()
