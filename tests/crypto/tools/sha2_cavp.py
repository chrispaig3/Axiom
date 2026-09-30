"""Extract NIST CAVP's byte-oriented SHA-256, SHA-384 and SHA-512
known answers (SHAVS) into tests/crypto/vectors/.

    python3 tests/crypto/tools/sha2_cavp.py --long-every 8

Writes:
  sha2-cavp-msg.txt    fields: alg msg md    (every ShortMsg case, and
                       every Nth LongMsg case counting from the first)
  sha2-cavp-monte.txt  fields: alg seed md   (every Monte checkpoint: md
                       is the checkpoint reached from seed by SHAVS
                       section 6.4's 1000 iterations)
`alg` is 256, 384 or 512.
"""
import argparse
import io
import zipfile

from hashfam_util import fetch, hx, rsp_records, write

URL = ("https://csrc.nist.gov/CSRC/media/Projects/"
       "Cryptographic-Algorithm-Validation-Program/documents/shs/"
       "shabytetestvectors.zip")
SHA256 = "929ef80b7b3418aca026643f6f248815913b60e01741a44bba9e118067f4c9b8"
ALGS = ["256", "384", "512"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--long-every", type=int, required=True)
    args = ap.parse_args()
    z = zipfile.ZipFile(io.BytesIO(fetch(URL, SHA256)))

    def member(name):
        path = f"shabytetestvectors/{name}"
        return z.read(path).decode("ascii")

    msg_lines = []
    for alg in ALGS:
        for kind, every in (("ShortMsg", 1), ("LongMsg", args.long_every)):
            recs = [r for r in rsp_records(member(f"SHA{alg}{kind}.rsp")) if "MD" in r]
            for i, r in enumerate(recs):
                if i % every:
                    continue
                n = int(r["Len"])
                assert n % 8 == 0
                msg = bytes.fromhex(r["Msg"])[: n // 8]
                msg_lines.append(f"{alg} {hx(msg)} {r['MD'].lower()}")
    monte_lines = []
    for alg in ALGS:
        seed = None
        for r in rsp_records(member(f"SHA{alg}Monte.rsp")):
            if "Seed" in r:
                seed = r["Seed"].lower()
            elif "MD" in r:
                md = r["MD"].lower()
                monte_lines.append(f"{alg} {seed} {md}")
                seed = md
    common = [
        f"source: {URL} (CAVP SHS byte-oriented vectors, retrieved 2026-09-29)",
        f"sha256: {SHA256}",
    ]
    write("sha2-cavp-msg.txt", common + [
        f"extract: tests/crypto/tools/sha2_cavp.py --long-every {args.long_every}",
        f"selection: SHA{{256,384,512}}ShortMsg.rsp whole; SHA{{256,384,512}}LongMsg.rsp cases 0, {args.long_every}, {2 * args.long_every}, ...",
        "fields: alg msg md",
    ], msg_lines)
    write("sha2-cavp-monte.txt", common + [
        f"extract: tests/crypto/tools/sha2_cavp.py --long-every {args.long_every}",
        "selection: SHA{256,384,512}Monte.rsp whole; each line is one checkpoint and the seed it starts from",
        "fields: alg seed md",
    ], monte_lines)


if __name__ == "__main__":
    main()
