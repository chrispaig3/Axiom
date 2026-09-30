"""NIST's ACVP known answers for ML-KEM (FIPS 203).

    python3 tests/crypto/tools/mlkem_acvp.py

Reads the ACVP-Server gen-val JSON files at a pinned commit - the
prompt and the expected results of ML-KEM-keyGen-FIPS203 and
ML-KEM-encapDecap-FIPS203, and of ML-KEM-encapDecap-FIPS203-tr1 the
decapsulation groups whose key is given as a seed - and writes:

- mlkem-acvp-keygen.txt: tcId set d z ek dkpke hek. The expected
  decapsulation key is dkpke || ek || hek || z; the script checks that
  the official dk is exactly that before splitting it, so the file
  determines it without repeating ek.
- mlkem-acvp-encap.txt: tcId set ek m c k (the encapsulation groups).
- mlkem-acvp-decap.txt: tcId set format key c k, where `format` is
  `expanded` (key is dk; the FIPS203 file) or `seed` (key is d || z;
  the tr1 file's seed-format groups).
- mlkem-acvp-keycheck.txt: tcId set kind key passed, `kind` being `ek`
  (encapsulationKeyCheck, section 7.2) or `dk`
  (decapsulationKeyCheck, section 7.3), `passed` 1 or 0.

`set` is 512, 768 or 1024. tcIds are the files' own; those of the tr1
file carry a `tr1-` prefix.
"""
import hashlib
import json
import sys

from mlkem_util import NAMES, SETS, fetch, hx, params, split_dk, write

COMMIT = "975de31eb83d87039ec88934fdc47d8c312b892d"
BASE = f"https://raw.githubusercontent.com/usnistgov/ACVP-Server/{COMMIT}/gen-val/json-files/"
FILES = {
    "ML-KEM-keyGen-FIPS203": ("3f9ce34f6c836c77958bad2729e837c3b213f44ac36c3065976e7acca6389523",
                              "a253d0ad91c95ebea5b409673defef0aa49d65d4ed72286399e2e798ddf073a4"),
    "ML-KEM-encapDecap-FIPS203": ("998e22dfb12efb14ce9fdff911ca634b13612819a1806f25da69adba7e16db91",
                                  "9089ec6ff2424da9f2782b89b2f831a329a3e28d6e5e24b802b78ff36ac61cdf"),
    "ML-KEM-encapDecap-FIPS203-tr1": ("a25430d886a8212a21ed0d4015eb91aa30d555588465d47da04ffb45236d27fd",
                                      "aa846067d30bebcfe4e839b076b1df5cdeb14332912b3e02dfe8d00c614098b4"),
}


def load(name):
    p_sha, e_sha = FILES[name]
    prompt = json.loads(fetch(BASE + name + "/prompt.json", p_sha))
    expected = json.loads(fetch(BASE + name + "/expectedResults.json", e_sha))
    pairs = []
    for g, ge in zip(prompt["testGroups"], expected["testGroups"]):
        if g["tgId"] != ge["tgId"]:
            sys.exit(f"{name}: groups out of step")
        res = {t["tcId"]: t for t in ge["tests"]}
        for t in g["tests"]:
            pairs.append((g, t, res[t["tcId"]]))
    return pairs


def b(s):
    return bytes.fromhex(s)


def main():
    header = lambda name: [f"source: {BASE}{name}/prompt.json and expectedResults.json",
                           "sha256: " + " ".join(FILES[name]) + " (prompt, expectedResults)"]
    keygen = []
    for g, t, r in load("ML-KEM-keyGen-FIPS203"):
        k = SETS[g["parameterSet"]]
        ek, dk = b(r["ek"]), b(r["dk"])
        dkpke, ek2, hek, z = split_dk(dk, k)
        if len(ek) != params(k)[0] or len(dk) != params(k)[1] or ek2 != ek \
                or hek != hashlib.sha3_256(ek).digest() or z != b(t["z"]):
            sys.exit(f"keyGen tcId {t['tcId']}: dk is not dk_PKE || ek || H(ek) || z")
        keygen.append(f"{t['tcId']} {NAMES[k]} {t['d'].lower()} {t['z'].lower()} {hx(ek)} {hx(dkpke)} {hx(hek)}")
    write("mlkem-acvp-keygen.txt", header("ML-KEM-keyGen-FIPS203") + [
        "extract: tests/crypto/tools/mlkem_acvp.py",
        "selection: every test of every group",
        "fields: tcId set d z ek dkpke hek"], keygen)

    encap, decap, check = [], [], []
    for g, t, r in load("ML-KEM-encapDecap-FIPS203"):
        k = SETS[g["parameterSet"]]
        f = g["function"]
        if f == "encapsulation":
            encap.append(f"{t['tcId']} {NAMES[k]} {t['ek'].lower()} {t['m'].lower()} {r['c'].lower()} {r['k'].lower()}")
        elif f == "decapsulation":
            decap.append(f"{t['tcId']} {NAMES[k]} expanded {t['dk'].lower()} {t['c'].lower()} {r['k'].lower()}")
        elif f == "encapsulationKeyCheck":
            check.append(f"{t['tcId']} {NAMES[k]} ek {t['ek'].lower()} {int(r['testPassed'])}")
        elif f == "decapsulationKeyCheck":
            check.append(f"{t['tcId']} {NAMES[k]} dk {t['dk'].lower()} {int(r['testPassed'])}")
        else:
            sys.exit(f"unknown function {f}")
    for g, t, r in load("ML-KEM-encapDecap-FIPS203-tr1"):
        k = SETS[g["parameterSet"]]
        if g["function"] == "decapsulation" and g.get("keyFormat") == "seed":
            decap.append(f"tr1-{t['tcId']} {NAMES[k]} seed {t['d'].lower()}{t['z'].lower()} {t['c'].lower()} {r['k'].lower()}")
    common = ["extract: tests/crypto/tools/mlkem_acvp.py"]
    write("mlkem-acvp-encap.txt", header("ML-KEM-encapDecap-FIPS203") + common + [
        "selection: every test of the encapsulation groups",
        "fields: tcId set ek m c k"], encap)
    write("mlkem-acvp-decap.txt", header("ML-KEM-encapDecap-FIPS203") + [
        "source: " + BASE + "ML-KEM-encapDecap-FIPS203-tr1/prompt.json and expectedResults.json",
        "sha256: " + " ".join(FILES["ML-KEM-encapDecap-FIPS203-tr1"]) + " (tr1 prompt, expectedResults)"] + common + [
        "selection: every decapsulation test of FIPS203, and the tr1 decapsulation groups with keyFormat seed",
        "fields: tcId set format key c k"], decap)
    write("mlkem-acvp-keycheck.txt", header("ML-KEM-encapDecap-FIPS203") + common + [
        "selection: every test of the encapsulationKeyCheck and decapsulationKeyCheck groups",
        "fields: tcId set kind key passed"], check)


if __name__ == "__main__":
    main()
