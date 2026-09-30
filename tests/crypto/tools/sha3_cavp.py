"""Extract NIST CAVP's byte-oriented SHA-3 and SHAKE known answers
(SHA3VS and SHAKEVS) into tests/crypto/vectors/.

    python3 tests/crypto/tools/sha3_cavp.py --long-every 10 --varout-every 4

Writes:
  sha3-cavp-msg.txt     fields: alg msg md
      every SHA3_{224,256,384,512}ShortMsg case, and every Nth LongMsg
      case counting from the first
  sha3-cavp-monte.txt   fields: alg seed md
      every Monte checkpoint: md is 1000 iterations of md = SHA3(md)
      from seed
  shake-cavp-msg.txt    fields: alg outlen msg output
      every SHAKE{128,256}ShortMsg case, every Nth LongMsg case and
      every Mth VariableOut case, each counting from the first; outlen
      in bytes
  shake-cavp-monte.txt  fields: alg minlen maxlen outlen prev output
      every Monte checkpoint, made independent of the one before: from
      `prev` (the previous checkpoint's output, or the initial Msg),
      1000 iterations of output = SHAKE(first 16 bytes of the previous
      output, zero-padded to 16, outlen bytes), each iteration's outlen
      being minlen + (its predecessor's last two bytes, big-endian,
      mod (maxlen - minlen + 1)); `outlen` is the first iteration's,
      which SHAKEVS section 6.3.3 derives from `prev` the same way, or
      maxlen for the first checkpoint. Lengths in bytes.
"""
import argparse
import io
import zipfile

from hashfam_util import fetch, hx, rsp_records, write

SHA3_URL = ("https://csrc.nist.gov/CSRC/media/Projects/"
            "Cryptographic-Algorithm-Validation-Program/documents/sha3/"
            "sha-3bytetestvectors.zip")
SHA3_SHA256 = "cd07701af2e47f5cc889d642528b4bf11f8b6eb55797c7307a96828ed8d8fc8c"
SHAKE_URL = ("https://csrc.nist.gov/CSRC/media/Projects/"
             "Cryptographic-Algorithm-Validation-Program/documents/sha3/"
             "shakebytetestvectors.zip")
SHAKE_SHA256 = "debfebc3157b3ceea002b84ca38476420389a3bf7e97dc5f53ea4689a16de4c7"


def msg_of(r):
    n = int(r["Len"])
    assert n % 8 == 0
    return bytes.fromhex(r["Msg"])[: n // 8]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--long-every", type=int, required=True)
    ap.add_argument("--varout-every", type=int, required=True)
    args = ap.parse_args()
    sz = zipfile.ZipFile(io.BytesIO(fetch(SHA3_URL, SHA3_SHA256)))
    kz = zipfile.ZipFile(io.BytesIO(fetch(SHAKE_URL, SHAKE_SHA256)))

    def member(z, name):
        [path] = [n for n in z.namelist() if n.split("/")[-1] == name]
        return z.read(path).decode("ascii")

    extract = (f"extract: tests/crypto/tools/sha3_cavp.py --long-every {args.long_every}"
               f" --varout-every {args.varout_every}")
    sha3_src = [f"source: {SHA3_URL} (CAVP SHA-3 byte-oriented vectors, retrieved 2026-09-29)",
                f"sha256: {SHA3_SHA256}", extract]
    shake_src = [f"source: {SHAKE_URL} (CAVP SHAKE byte-oriented vectors, retrieved 2026-09-29)",
                 f"sha256: {SHAKE_SHA256}", extract]

    lines = []
    for alg in ("224", "256", "384", "512"):
        for kind, every in (("ShortMsg", 1), ("LongMsg", args.long_every)):
            recs = [r for r in rsp_records(member(sz, f"SHA3_{alg}{kind}.rsp")) if "MD" in r]
            for i, r in enumerate(recs):
                if i % every == 0:
                    lines.append(f"{alg} {hx(msg_of(r))} {r['MD'].lower()}")
    write("sha3-cavp-msg.txt", sha3_src + [
        f"selection: SHA3_{{224,256,384,512}}ShortMsg.rsp whole; LongMsg.rsp cases 0, {args.long_every}, {2 * args.long_every}, ...",
        "fields: alg msg md"], lines)

    lines = []
    for alg in ("224", "256", "384", "512"):
        seed = None
        for r in rsp_records(member(sz, f"SHA3_{alg}Monte.rsp")):
            if "Seed" in r:
                seed = r["Seed"].lower()
            elif "MD" in r:
                md = r["MD"].lower()
                lines.append(f"{alg} {seed} {md}")
                seed = md
    write("sha3-cavp-monte.txt", sha3_src + [
        "selection: SHA3_{224,256,384,512}Monte.rsp whole; each line is one checkpoint and the seed it starts from",
        "fields: alg seed md"], lines)

    lines = []
    for alg in ("128", "256"):
        for kind, every in (("ShortMsg", 1), ("LongMsg", args.long_every)):
            recs = [r for r in rsp_records(member(kz, f"SHAKE{alg}{kind}.rsp")) if "Output" in r]
            for i, r in enumerate(recs):
                if i % every == 0:
                    out = bytes.fromhex(r["Output"])
                    outlen = int(r["section"].split("=")[1]) // 8
                    assert outlen == len(out)
                    lines.append(f"{alg} {outlen} {hx(msg_of(r))} {out.hex()}")
        recs = [r for r in rsp_records(member(kz, f"SHAKE{alg}VariableOut.rsp")) if "Output" in r]
        for i, r in enumerate(recs):
            if i % args.varout_every == 0:
                out = bytes.fromhex(r["Output"])
                assert int(r["Outputlen"]) == 8 * len(out)
                lines.append(f"{alg} {len(out)} {hx(bytes.fromhex(r['Msg']))} {out.hex()}")
    write("shake-cavp-msg.txt", shake_src + [
        f"selection: SHAKE{{128,256}}ShortMsg.rsp whole; LongMsg.rsp cases 0, {args.long_every}, ...; VariableOut.rsp cases 0, {args.varout_every}, ...",
        "fields: alg outlen msg output"], lines)

    lines = []
    for alg in ("128", "256"):
        text = member(kz, f"SHAKE{alg}Monte.rsp")
        minlen = maxlen = None
        for raw in text.splitlines():
            if raw.startswith("[Minimum Output Length (bits) ="):
                minlen = int(raw.split("=")[1].strip(" ]")) // 8
            if raw.startswith("[Maximum Output Length (bits) ="):
                maxlen = int(raw.split("=")[1].strip(" ]")) // 8
        prev, outlen = None, maxlen
        for r in rsp_records(text):
            if "Msg" in r:
                prev = bytes.fromhex(r["Msg"])
            elif "Output" in r:
                out = bytes.fromhex(r["Output"])
                lines.append(f"{alg} {minlen} {maxlen} {outlen} {prev.hex()} {out.hex()}")
                outlen = minlen + int.from_bytes(out[-2:], "big") % (maxlen - minlen + 1)
                prev = out
    write("shake-cavp-monte.txt", shake_src + [
        "selection: SHAKE{128,256}Monte.rsp whole; each line is one checkpoint, its starting output and its first iteration's length",
        "fields: alg minlen maxlen outlen prev output"], lines)


if __name__ == "__main__":
    main()
