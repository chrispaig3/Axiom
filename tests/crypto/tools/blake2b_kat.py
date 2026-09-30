"""Extract the BLAKE2 team's BLAKE2b known answers into
tests/crypto/vectors/blake2b-kat.txt.

    python3 tests/crypto/tools/blake2b_kat.py

The source is testvectors/blake2-kat.json from github.com/BLAKE2/BLAKE2
at a pinned commit: every "blake2b" entry, which is the 64-byte digest of
the messages 00, 0001, ..., 00..fe (0 to 255 bytes), once unkeyed and
once keyed with the 64 bytes 00..3f.

Fields: key msg out (`-` for an empty key or message).
"""
import json

from hashfam_util import fetch, write

COMMIT = "ed1974ea83433eba7b2d95c5dcd9ac33cb847913"
URL = f"https://raw.githubusercontent.com/BLAKE2/BLAKE2/{COMMIT}/testvectors/blake2-kat.json"
SHA256 = "5031ac14800798ae15cee79c04d65e326a575f2c968c7e2846a79bd07a1c0e61"


def main():
    cases = [c for c in json.loads(fetch(URL, SHA256)) if c["hash"] == "blake2b"]
    lines = [f"{c['key'] or '-'} {c['in'] or '-'} {c['out']}" for c in cases]
    write("blake2b-kat.txt", [
        f"source: {URL}",
        f"sha256: {SHA256}",
        "extract: tests/crypto/tools/blake2b_kat.py",
        "selection: every entry whose hash is blake2b (256 unkeyed, 256 keyed)",
        "fields: key msg out",
    ], lines)


if __name__ == "__main__":
    main()
