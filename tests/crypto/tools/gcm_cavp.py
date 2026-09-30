"""NIST's CAVP GCM test vectors, for AES-128-GCM and AES-256-GCM.

    python3 tests/crypto/tools/gcm_cavp.py

Writes tests/crypto/vectors/gcm-cavp.txt from gcmtestvectors.zip:
gcmEncryptExtIV128.rsp, gcmEncryptExtIV256.rsp, gcmDecrypt128.rsp and
gcmDecrypt256.rsp, every case in the groups with a 96-bit IV and a
128-bit tag (the only IV and tag lengths Crypto.AesGcm offers). The
192-bit files are left out because 192-bit keys are not offered.

Fields: id kind key iv aad pt ct tag. `kind` is `encrypt` (seal pt
and expect ct || tag), `decrypt` (open ct || tag and expect pt) or
`fail` (a decrypt case NIST marks FAIL: open must refuse it; pt is
`-`).
"""
import io
import sys
import zipfile

from aead_util import fetch, write

URL = ("https://csrc.nist.gov/CSRC/media/Projects/"
       "Cryptographic-Algorithm-Validation-Program/documents/mac/gcmtestvectors.zip")
SHA256 = "f9fc479e134cde2980b3bb7cddbcb567b2cd96fd753835243ed067699f26a023"
FILES = ["gcmEncryptExtIV128.rsp", "gcmEncryptExtIV256.rsp",
         "gcmDecrypt128.rsp", "gcmDecrypt256.rsp"]


def f(v):
    return v.lower() if v else "-"


def cases(name, text, decrypt):
    out = []
    params = {}
    rec = None

    def flush():
        if rec is None:
            return
        if params.get("IVlen") != "96" or params.get("Taglen") != "128":
            return
        cid = f"{name}#{params['Keylen']}/{params['PTlen']}/{params['AADlen']}/{rec['Count']}"
        if decrypt:
            kind = "fail" if rec.get("FAIL") else "decrypt"
            pt = "-" if rec.get("FAIL") else f(rec["PT"])
        else:
            kind = "encrypt"
            pt = f(rec["PT"])
        out.append(f"{cid} {kind} {f(rec['Key'])} {f(rec['IV'])} {f(rec['AAD'])} {pt} {f(rec['CT'])} {f(rec['Tag'])}")

    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            flush()
            rec = None
            k, v = line[1:-1].split(" = ")
            params[k] = v
        elif line.startswith("Count = "):
            flush()
            rec = {"Count": line.split(" = ")[1]}
        elif line == "FAIL":
            rec["FAIL"] = True
        elif " = " in line or line.endswith(" ="):
            k, _, v = line.partition(" =")
            rec[k] = v.strip()
    flush()
    return out


def main():
    z = zipfile.ZipFile(io.BytesIO(fetch(URL, SHA256)))
    lines = []
    for name in FILES:
        got = cases(name[:-4], z.read(name).decode("ascii"), name.startswith("gcmDecrypt"))
        if len(got) != 375:
            sys.exit(f"{name}: {len(got)} cases with a 96-bit IV and 128-bit tag, expected 375")
        lines += got
    write("gcm-cavp.txt", [
        f"source: {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/gcm_cavp.py",
        "selection: gcmEncryptExtIV128/256 and gcmDecrypt128/256, every case with IVlen = 96 and Taglen = 128",
        "fields: id kind key iv aad pt ct tag",
    ], lines)


if __name__ == "__main__":
    main()
