"""NIST's AESAVS known-answer vectors for the raw AES block cipher.

    python3 tests/crypto/tools/aes_cavp.py

Writes tests/crypto/vectors/aes-kat-ecb.txt from KAT_AES.zip (the
CAVP "AES Known Answer Test" files of AESAVS, appendices B to E): the
twelve ECB files, GFSbox, KeySbox, VarKey and VarTxt for 128-, 192-
and 256-bit keys, every case of both their ENCRYPT and DECRYPT
sections. ECB is AES applied to one block, so these are known answers
for the cipher itself. Fields: id dir key input output, where `dir` is
`encrypt` or `decrypt` and `id` is the file stem and COUNT.
"""
import io
import sys
import zipfile

from aead_util import fetch, write

URL = ("https://csrc.nist.gov/CSRC/media/Projects/"
       "Cryptographic-Algorithm-Validation-Program/documents/aes/KAT_AES.zip")
SHA256 = "a203b16c9246b2ebae31dee5de21a606be80cf78ceabaca37150236fa098eb60"
FILES = [f"ECB{kind}{bits}.rsp"
         for kind in ("GFSbox", "KeySbox", "VarKey", "VarTxt")
         for bits in (128, 192, 256)]


def cases(name, text):
    """(id, dir, key, input, output) for each case of one .rsp file."""
    out = []
    section = None
    rec = {}
    for raw in text.splitlines():
        line = raw.strip()
        if line == "[ENCRYPT]":
            section = "encrypt"
        elif line == "[DECRYPT]":
            section = "decrypt"
        elif " = " in line:
            k, v = line.split(" = ", 1)
            rec[k] = v.lower()
            if section == "encrypt" and k == "CIPHERTEXT" or section == "decrypt" and k == "PLAINTEXT":
                if section == "encrypt":
                    inp, outp = rec["PLAINTEXT"], rec["CIPHERTEXT"]
                else:
                    inp, outp = rec["CIPHERTEXT"], rec["PLAINTEXT"]
                out.append((f"{name}#{rec['COUNT']}", section, rec["KEY"], inp, outp))
                rec = {}
    return out


def main():
    z = zipfile.ZipFile(io.BytesIO(fetch(URL, SHA256)))
    lines = []
    for f in FILES:
        got = cases(f[:-4], z.read(f).decode("ascii"))
        if not got:
            sys.exit(f"{f}: no cases read")
        for (cid, d, key, inp, outp) in got:
            if len(key) not in (32, 48, 64) or len(inp) != 32 or len(outp) != 32:
                sys.exit(f"{cid}: unexpected field lengths")
            lines.append(f"{cid} {d} {key} {inp} {outp}")
    write("aes-kat-ecb.txt", [
        f"source: {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/aes_cavp.py",
        "selection: the 12 ECB files (GFSbox, KeySbox, VarKey, VarTxt x 128, 192, 256), both sections, every case",
        "fields: id dir key input output",
    ], lines)


if __name__ == "__main__":
    main()
