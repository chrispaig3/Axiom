"""NIST ACVP known answers for ML-DSA (FIPS 204).

    python3 tests/crypto/tools/mldsa_acvp.py

Reads the ML-DSA-keyGen-FIPS204, ML-DSA-sigGen-FIPS204 and
ML-DSA-sigVer-FIPS204 internalProjection.json files of
usnistgov/ACVP-Server at a pinned commit and writes three vector files.
Long expected outputs are carried as their SHA-256, which the tests
recompute from what they produce.

  mldsa-acvp-keygen.txt   set seed pkSha256 skSha256
      every keyGen case (25 per parameter set).
  mldsa-acvp-siggen.txt   key set sk
                          sign set iface rnd ctx msg sigSha256
      each `sign` line uses the `key` line before it. `iface` is pure
      (ML-DSA.Sign: `msg` with context `ctx`), internal (Sign_internal:
      `msg` is M') or mu (Sign_internal from mu: `msg` is mu). `rnd` is
      `-` for deterministic signing. Selection: from every pure,
      internal and external-mu group the two cases with the shortest
      message (ties by tcId); from every pre-hash group the one with the
      shortest message, turned into an `internal` case by formatting
      HashML-DSA's M' here (FIPS 204 Algorithm 4, the pre-hash computed
      with hashlib).
  mldsa-acvp-sigver.txt   verify set iface ctx msg pk sig expect
      `expect` is 01 when the signature must verify, else 00.
      Selection: from every pure, internal and external-mu group, for
      each of the five reasons (valid, modified message, modified z,
      modified hint, modified commitment), the case with the shortest
      message. Pre-hash groups are left out here.
"""
import json
import sys

from mldsa_util import fetch, hx, prehash_mprime, sha, write

COMMIT = "975de31eb83d87039ec88934fdc47d8c312b892d"
BASE = f"https://raw.githubusercontent.com/usnistgov/ACVP-Server/{COMMIT}/gen-val/json-files"
FILES = {
    "keygen": ("ML-DSA-keyGen-FIPS204", "e67ee6540d40e11506c3c4e3b1f79fc1cefcd49820db99fc61f87cc8ba463baf"),
    "siggen": ("ML-DSA-sigGen-FIPS204", "72dcaf5f69853ca267ccd16af9cb40949786aca0fcfbf05d1ebeba132b93af22"),
    "sigver": ("ML-DSA-sigVer-FIPS204", "47cdd6314c7f746d02421ffcba89d4dbc7bb875ac49e07a029fdfc26fba55437"),
}


def load(which):
    d, digest = FILES[which]
    url = f"{BASE}/{d}/internalProjection.json"
    return url, digest, json.loads(fetch(url, digest, cache_name=f"{d}.json"))


def pset(g):
    return int(g["parameterSet"].split("-")[-1])


def b(t, key):
    return bytes.fromhex(t.get(key, ""))


def shape(g, t):
    """(iface, ctx, msg) for a sigGen or sigVer case: pre-hash cases
    become internal ones with HashML-DSA's M' formatted here."""
    if g["preHash"] == "preHash":
        return "internal", b"", prehash_mprime(b(t, "context"), b(t, "message"), t["hashAlg"])
    if g["signatureInterface"] == "external":
        return "pure", b(t, "context"), b(t, "message")
    if g.get("externalMu"):
        return "mu", b"", b(t, "mu")
    return "internal", b"", b(t, "message")


def shortest(tests, n):
    return sorted(tests, key=lambda t: (len(t.get("message", t.get("mu", ""))), t["tcId"]))[:n]


def header(url, digest, fields, selection=None):
    h = [f"source: {url}", f"sha256: {digest}", "extract: tests/crypto/tools/mldsa_acvp.py"]
    if selection:
        h.append(f"selection: {selection}")
    return h + [f"fields: {fields}"]


def main():
    url, digest, data = load("keygen")
    lines = []
    for g in data["testGroups"]:
        for t in g["tests"]:
            lines.append(f"{pset(g)} {t['seed'].lower()} {sha(b(t, 'pk'))} {sha(b(t, 'sk'))}")
    if len(lines) != 75:
        sys.exit(f"keyGen: {len(lines)} cases, expected 75")
    write("mldsa-acvp-keygen.txt", header(url, digest, "set seed pkSha256 skSha256"), lines)

    url, digest, data = load("siggen")
    lines = []
    for g in data["testGroups"]:
        if g.get("cornerCase", "none") != "none":
            sys.exit(f"sigGen group {g['tgId']}: corner case {g['cornerCase']}")
        take = 1 if g["preHash"] == "preHash" else 2
        for t in shortest(g["tests"], take):
            iface, ctx, msg = shape(g, t)
            rnd = "-" if g["deterministic"] else t["rnd"].lower()
            lines.append(f"key {pset(g)} {t['sk'].lower()}")
            lines.append(f"sign {pset(g)} {iface} {rnd} {hx(ctx)} {hx(msg)} {sha(b(t, 'signature'))}")
    write("mldsa-acvp-siggen.txt", header(url, digest, "key set sk | sign set iface rnd ctx msg sigSha256",
                                          "two shortest-message cases per pure, internal and mu group; one per pre-hash group, as internal"),
          lines)

    url, digest, data = load("sigver")
    lines = []
    for g in data["testGroups"]:
        if g["preHash"] == "preHash":
            continue
        by_reason = {}
        for t in g["tests"]:
            by_reason.setdefault(t["reason"], []).append(t)
        if len(by_reason) != 5:
            sys.exit(f"sigVer group {g['tgId']}: {len(by_reason)} reasons")
        for reason in sorted(by_reason):
            t = shortest(by_reason[reason], 1)[0]
            iface, ctx, msg = shape(g, t)
            expect = "01" if t["testPassed"] else "00"
            lines.append(f"verify {pset(g)} {iface} {hx(ctx)} {hx(msg)} {t['pk'].lower()} {t['signature'].lower()} {expect}")
    write("mldsa-acvp-sigver.txt", header(url, digest, "verify set iface ctx msg pk sig expect",
                                          "per pure, internal and mu group, the shortest-message case of each of the five reasons"),
          lines)


if __name__ == "__main__":
    main()
