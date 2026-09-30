"""Wycheproof's ML-DSA vectors.

    python3 tests/crypto/tools/mldsa_wycheproof.py

Reads testvectors_v1/mldsa_{44,65,87}_{sign_seed,sign_noseed,verify}_test.json
at a pinned commit and writes two vector files.

  wycheproof-mldsa-sign.txt
      seed set xi ok          a key from the group's 32-byte seed
      key set sk ok           a key from the group's private key encoding
      sign set tcId iface rnd ctx msg result sigSha256
      `ok` is 01 when the key must be accepted, 00 when its length or
      contents must be refused. Each `sign` line uses the key line
      before it. `iface` is pure (msg with context ctx) or mu (msg is
      mu, for Sign_internal); `rnd` is `-` for deterministic signing;
      `result` is valid, or invalid when signing must be refused (a
      context over 255 bytes); `sigSha256` is `-` when there is no
      signature. Every case of every sign_seed and sign_noseed file.
  wycheproof-mldsa-verify.txt
      pk set pk pkSha256      the group's public key (possibly the wrong
                              length), and its SHA-256, which the test checks
      verify set tcId ctx msg sig result
      Selection: for each parameter set, every case flagged
      InvalidHintsEncoding or ModifiedSignature (each breaks a different
      rule or region), and of every other combination of flags and
      result the first three cases in file order. The cases left out
      repeat a check already kept (most are forty-odd norm violations
      and forty-odd many-iteration signatures per set).
"""
import json
import sys

from mldsa_util import fetch, hx, sha, write

COMMIT = "3fa63dd0344abb611f1fb1d77e119938603ea230"
BASE = f"https://raw.githubusercontent.com/C2SP/wycheproof/{COMMIT}/testvectors_v1"
SHA256 = {
    "mldsa_44_sign_noseed_test.json": "ee55e18b1944db496b2539d3884dfacc04a96db21bcec239063df5e4cd1ee6cb",
    "mldsa_44_sign_seed_test.json": "b29b0dcca2e52c988e1b9c06f8b521889ffbaadfc6a9dbf52f0f0f8f4c5b6b92",
    "mldsa_44_verify_test.json": "0ca1b5df4575263e29b31fae7569a3da41df9a3b6fee56720a992d0cd1153b68",
    "mldsa_65_sign_noseed_test.json": "8587a53e7e3ca20b006b661316b89c762acdecf3fa902746b01cbc09fe14130d",
    "mldsa_65_sign_seed_test.json": "d72e9c2f514c9f7490c33785ae0027d942ba2c45a9b8ebfc8fb1802b4913bf38",
    "mldsa_65_verify_test.json": "49ac366d76115eab56b7116f10d06e288e6f23fe6cfb90b26bfb2d731a8d1e02",
    "mldsa_87_sign_noseed_test.json": "bd4c997f1fb90d985dbcca9a5ab52cef1f5c22d2cc0ba332d8dbe68703a5b40d",
    "mldsa_87_sign_seed_test.json": "e83c292318134faa6af777e86c619c4643e2705dba91dfa5adcd1fddfd4f40ce",
    "mldsa_87_verify_test.json": "e9e04216d4217265a5affba2568476d35742dbd8ffc9d4c23b3441334a08a224",
}
KEEP_ALL = {("InvalidHintsEncoding",), ("ModifiedSignature",)}
CAP = 3


def load(name):
    return json.loads(fetch(f"{BASE}/{name}", SHA256[name]))


def sign_line(s, t):
    if "mu" in t and "msg" not in t:
        iface, msg = "mu", t["mu"]
    else:
        iface, msg = "pure", t["msg"]
    rnd = t.get("rnd", "") or "-"
    sig = bytes.fromhex(t.get("sig", ""))
    if t["result"] not in ("valid", "invalid"):
        sys.exit(f"sign tcId {t['tcId']}: result {t['result']}")
    return (f"sign {s} {t['tcId']} {iface} {rnd} {hx(bytes.fromhex(t.get('ctx', '')))} "
            f"{hx(bytes.fromhex(msg))} {t['result']} {sha(sig) if sig else '-'}")


def key_ok(group_tests):
    """01 unless every case of the group is refused for the key itself."""
    bad = {"IncorrectPrivateKeyLength", "InvalidPrivateKey"}
    return "00" if all(t["result"] == "invalid" and bad & set(t["flags"]) for t in group_tests) else "01"


def main():
    sign, verify = [], []
    sources = []
    for s in (44, 65, 87):
        name = f"mldsa_{s}_sign_seed_test.json"
        sources.append(name)
        for g in load(name)["testGroups"]:
            sign.append(f"seed {s} {hx(bytes.fromhex(g['privateSeed']))} {key_ok(g['tests'])}")
            sign += [sign_line(s, t) for t in g["tests"]]
        name = f"mldsa_{s}_sign_noseed_test.json"
        sources.append(name)
        for g in load(name)["testGroups"]:
            sign.append(f"key {s} {hx(bytes.fromhex(g['privateKey']))} {key_ok(g['tests'])}")
            sign += [sign_line(s, t) for t in g["tests"]]
        name = f"mldsa_{s}_verify_test.json"
        sources.append(name)
        seen = {}
        for g in load(name)["testGroups"]:
            kept = []
            for t in g["tests"]:
                flags = tuple(t["flags"])
                if flags not in KEEP_ALL:
                    key = (t["result"], flags)
                    seen[key] = seen.get(key, 0) + 1
                    if seen[key] > CAP:
                        continue
                if t["result"] not in ("valid", "invalid"):
                    sys.exit(f"verify tcId {t['tcId']}: result {t['result']}")
                kept.append(f"verify {s} {t['tcId']} {hx(bytes.fromhex(t.get('ctx', '')))} "
                            f"{hx(bytes.fromhex(t['msg']))} {hx(bytes.fromhex(t['sig']))} {t['result']}")
            if kept:
                pk = bytes.fromhex(g["publicKey"])
                verify.append(f"pk {s} {hx(pk)} {sha(pk)}")
                verify += kept
    src = [f"source: {BASE}/<file> for " + ", ".join(sources)]
    digests = ["sha256: " + ", ".join(f"{n} {SHA256[n]}" for n in sources)]
    write("wycheproof-mldsa-sign.txt", src + digests + [
        "extract: tests/crypto/tools/mldsa_wycheproof.py",
        "selection: every case of the sign_seed and sign_noseed files",
        "fields: seed set xi ok | key set sk ok | sign set tcId iface rnd ctx msg result sigSha256",
    ], sign)
    write("wycheproof-mldsa-verify.txt", src + digests + [
        "extract: tests/crypto/tools/mldsa_wycheproof.py",
        f"selection: per parameter set, every InvalidHintsEncoding and ModifiedSignature case, "
        f"and the first {CAP} cases of every other combination of flags and result",
        "fields: pk set pk pkSha256 | verify set tcId ctx msg sig result",
    ], verify)


if __name__ == "__main__":
    main()
