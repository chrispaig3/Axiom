"""Wycheproof's ML-KEM vectors, a documented subset of them.

    python3 tests/crypto/tools/mlkem_wycheproof.py

Reads testvectors_v1/mlkem_{512,768,1024}_{test,encaps_test,
keygen_seed_test,semi_expanded_decaps_test}.json at a pinned commit.
The full files are 8.3 MB, mostly repetitions of the same shape of
case, so each file contributes, in file order:

- mlkem_N_test.json (decapsulation from a seed): the first 3 tests
  of each distinct (comment, flags) pair, digits in the comment read
  as one wildcard, so "seeds 0" and "seeds 1" are the same shape ->
  wycheproof-mlkem-decaps.txt,
  fields tcId set result seed c K. The file's ek is left out: the
  ACVP key-generation vectors cover it.
- mlkem_N_encaps_test.json: the first 3 of each (comment, flags) pair
  -> wycheproof-mlkem-encaps.txt, fields tcId set result m ek c K.
- mlkem_N_keygen_seed_test.json: the first 5 tests ->
  wycheproof-mlkem-keygen.txt, fields tcId set seed ek dkpke hek, the
  official dk being checked here to equal dkpke || ek || hek || z.
- mlkem_N_semi_expanded_decaps_test.json: every test ->
  wycheproof-mlkem-expanded.txt, fields tcId set result flags dk c K,
  `flags` joined with commas or `-`.

`result` is Wycheproof's: valid or invalid (neither file has an
acceptable case).
"""
import collections
import re
import hashlib
import json
import sys

from mlkem_util import NAMES, SETS, fetch, hx, params, split_dk, write

COMMIT = "3fa63dd0344abb611f1fb1d77e119938603ea230"
BASE = f"https://raw.githubusercontent.com/C2SP/wycheproof/{COMMIT}/testvectors_v1/"
SHA = {
    "mlkem_512_test.json": "18bc5455d5bf8226b3ab1d1deb51f3ed7c44b3d90039eb25416d40fa77e76f20",
    "mlkem_768_test.json": "c59c067ae794c343df575dd90f6f7458f51881b11a22d6e9d8677c8d9ee21e90",
    "mlkem_1024_test.json": "17c5b764d78c05522f1980fcb41d82add573f11de5d13004ae0b83bf46d9c43a",
    "mlkem_512_encaps_test.json": "85a69664f2e8243f5085f01fb22f9635b100b16a8935cf2b2ac94c127511a20c",
    "mlkem_768_encaps_test.json": "9d4381f94c40853bba430245b94968b7390d9175aacd9f1ae4e250a71c78b713",
    "mlkem_1024_encaps_test.json": "da41e8daf57e40a6b334a722e3f56067817352f5583fdb2434da1a2cd611358e",
    "mlkem_512_keygen_seed_test.json": "877ae6f5550d0e802086e5812bdbd23c16afa31cd3bff9669cd9661d3fbf2d85",
    "mlkem_768_keygen_seed_test.json": "fde5abe284396f4cb3c4610b90d680f0b57782e94c3365c97aee59e24881ebe4",
    "mlkem_1024_keygen_seed_test.json": "cd9241bf5d65a78e005866ea2c660615c17f50caa9afc2b96fd1573cc65617b5",
    "mlkem_512_semi_expanded_decaps_test.json": "bb90c7997dc3695e52882608b7c79675a012c031dd50dc08e76c4775a762ad14",
    "mlkem_768_semi_expanded_decaps_test.json": "e4438ab7d4dd7b6ace7165e45aeed4403082f981f86300c8369f69d3d071060a",
    "mlkem_1024_semi_expanded_decaps_test.json": "a4a7c88152df3d8d4b3f33aad584167dfaff67195cfde08aac4b981030b4d05c",
}


def tests(name):
    data = json.loads(fetch(BASE + name, SHA[name]))
    out = []
    for g in data["testGroups"]:
        k = SETS[g["parameterSet"]]
        for t in g["tests"]:
            if t["result"] not in ("valid", "invalid"):
                sys.exit(f"{name} tcId {t['tcId']}: result {t['result']}")
            out.append((k, t))
    if len(out) != data["numberOfTests"]:
        sys.exit(f"{name}: {len(out)} tests read, the file says {data['numberOfTests']}")
    return out


def first(cases, limit):
    seen = collections.Counter()
    for (k, t) in cases:
        key = (re.sub(r"[0-9]+", "#", t.get("comment", "")), tuple(t.get("flags", [])))
        seen[key] += 1
        if seen[key] <= limit:
            yield (k, t)


def main():
    header = lambda files, rule, fields: [
        "source: " + BASE + "{" + ",".join(files) + "}",
        "sha256: " + " ".join(SHA[f] for f in files),
        "extract: tests/crypto/tools/mlkem_wycheproof.py",
        "selection: " + rule,
        "fields: " + fields]
    sizes = ("512", "768", "1024")

    files = [f"mlkem_{n}_test.json" for n in sizes]
    lines = []
    for f in files:
        for (k, t) in first(tests(f), 3):
            lines.append(f"{t['tcId']} {NAMES[k]} {t['result']} {hx(bytes.fromhex(t['seed']))} "
                         f"{hx(bytes.fromhex(t['c']))} {hx(bytes.fromhex(t['K']))}")
    write("wycheproof-mlkem-decaps.txt", header(files, "the first 3 tests of each (comment with its digits wildcarded, flags) pair", "tcId set result seed c K"), lines)

    files = [f"mlkem_{n}_encaps_test.json" for n in sizes]
    lines = []
    for f in files:
        for (k, t) in first(tests(f), 3):
            lines.append(f"{t['tcId']} {NAMES[k]} {t['result']} {hx(bytes.fromhex(t['m']))} "
                         f"{hx(bytes.fromhex(t['ek']))} {hx(bytes.fromhex(t['c']))} {hx(bytes.fromhex(t['K']))}")
    write("wycheproof-mlkem-encaps.txt", header(files, "the first 3 tests of each (comment with its digits wildcarded, flags) pair", "tcId set result m ek c K"), lines)

    files = [f"mlkem_{n}_keygen_seed_test.json" for n in sizes]
    lines = []
    for f in files:
        for (k, t) in tests(f)[:5]:
            ek, dk, seed = bytes.fromhex(t["ek"]), bytes.fromhex(t["dk"]), bytes.fromhex(t["seed"])
            dkpke, ek2, hek, z = split_dk(dk, k)
            if t["result"] != "valid" or ek2 != ek or hek != hashlib.sha3_256(ek).digest() or z != seed[32:]:
                sys.exit(f"{f} tcId {t['tcId']}: dk is not dk_PKE || ek || H(ek) || z")
            lines.append(f"{t['tcId']} {NAMES[k]} {hx(seed)} {hx(ek)} {hx(dkpke)} {hx(hek)}")
    write("wycheproof-mlkem-keygen.txt", header(files, "the first 5 tests of each file", "tcId set seed ek dkpke hek"), lines)

    files = [f"mlkem_{n}_semi_expanded_decaps_test.json" for n in sizes]
    lines = []
    for f in files:
        for (k, t) in tests(f):
            flags = ",".join(t.get("flags", [])) or "-"
            lines.append(f"{t['tcId']} {NAMES[k]} {t['result']} {flags} {hx(bytes.fromhex(t['dk']))} "
                         f"{hx(bytes.fromhex(t['c']))} {hx(bytes.fromhex(t.get('K', '')))}")
    write("wycheproof-mlkem-expanded.txt", header(files, "every test", "tcId set result flags dk c K"), lines)


if __name__ == "__main__":
    main()
