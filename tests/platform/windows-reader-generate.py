#!/usr/bin/env python3
"""Maintain the embedded freestanding reader; CI uses --check, never rewrite."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

BEGIN = "; BEGIN GENERATED WINDOWS READER"
END = "; END GENERATED WINDOWS READER"
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/platform/windows-reader.c"
TARGET = ROOT / "core/codegen.ax"


def digest(data):
    return hashlib.sha256(data.encode()).hexdigest()


def emitted(text):
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    return "\n".join(json.loads(m.group(1)) for m in re.finditer(
        r'\(emitLine cg\s*("(?:[^"\\]|\\.)*")\)', block)) + "\n"


def normalize(raw):
    lines = []
    comparison = 0
    for line in raw.splitlines():
        if (line.startswith((";", "source_filename", "target ", "attributes ", "!"))
                or "@llvm.lifetime." in line or line.startswith("declare ") and "@llvm." not in line):
            continue
        line = re.sub(r", ![a-zA-Z.]+ !\d+", "", line)
        line = re.sub(r" #\d+", "", line)
        if re.match(r"declare .*@llvm\.u(?:max|min)\.i64\(", line):
            continue
        # LLVM 18 legs consume compiler output too. Newer Clang's extra
        # poison-refining flags are optional optimizations, not ABI facts.
        line = re.sub(r"(getelementptr(?: inbounds)?) (?:nuw|nusw) ", r"\1 ", line)
        line = re.sub(r"(trunc|zext) (?:nuw |nsw |nneg )+", r"\1 ", line)
        line = line.replace("or disjoint ", "or ").replace("icmp samesign ", "icmp ")
        line = re.sub(r"\b(captures|range)\([^)]*\) ?", "", line)
        line = re.sub(r"\b(dso_local|noundef|nofree|nonnull|readonly|writeonly|local_unnamed_addr|unnamed_addr) ?", "", line)
        line = re.sub(r"^define (i64 @__axiom_win_reader_)", r"define internal \1", line)
        line = re.sub(r"\s+;.*$", "", line).rstrip()
        minimum = re.fullmatch(
            r"(\s*)(%[-\w.$]+) = (?:tail )?call i64 @llvm\.u(max|min)\.i64\(i64 ([^,]+), i64 ([^)]+)\)", line)
        if minimum:
            indent, result, operation, left, right = minimum.groups()
            # Named temporaries do not consume an LLVM numeric SSA slot.
            # Keep Clang's result number and all later numbered values intact.
            temporary = f"%__axiom_reader_compare_{comparison}"
            comparison += 1
            predicate = "ugt" if operation == "max" else "ult"
            lines.append(f"{indent}{temporary} = icmp {predicate} i64 {left}, {right}")
            line = f"{indent}{result} = select i1 {temporary}, i64 {left}, i64 {right}"
        if "@llvm." in line:
            raise ValueError(f"unsupported intrinsic in freestanding Windows reader: {line}")
        if line:
            lines.append(line)
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--clang", default="clang")
    args = ap.parse_args()
    source = SOURCE.read_text()
    target = TARGET.read_text()
    if args.check:
        block = target.split(BEGIN, 1)[1].split(END, 1)[0]
        expected_source = re.search(r"source-sha256: ([0-9a-f]+)", block).group(1)
        expected_ir = re.search(r"ir-sha256: ([0-9a-f]+)", block).group(1)
        embedded = emitted(target)
        if "@llvm." in embedded:
            raise SystemExit("Windows reader must not add LLVM archive dependencies; regenerate explicitly")
        if digest(source) != expected_source or digest(embedded) != expected_ir:
            raise SystemExit("Windows reader source/embedded LLVM drift; regenerate explicitly")
        print("Windows reader source and embedded LLVM digests agree")
        return
    raw = subprocess.run([args.clang, "-target", "aarch64-pc-windows-msvc", "-S", "-emit-llvm",
                          "-O1", "-ffreestanding", "-fno-builtin", "-fno-stack-protector",
                          str(SOURCE), "-o", "-"], check=True, text=True, capture_output=True).stdout
    ir = normalize(raw)
    body = (BEGIN + "\n; Generated from tests/platform/windows-reader.c; do not edit this block.\n"
            + f"; source-sha256: {digest(source)}\n; ir-sha256: {digest(ir)}\n"
            + "(pub :: emitWinReaderRuntime (-> CG CG))\n(pub fn (emitWinReaderRuntime cg)\n  {\n"
            + "".join("    (emitLine cg " + json.dumps(line) + ")\n" for line in ir.splitlines())
            + "    cg\n  })\n" + END)
    if BEGIN in target:
        before, rest = target.split(BEGIN, 1)
        _, after = rest.split(END, 1)
        target = before + body + after
    else:
        at = target.index("; What a bare-metal module carries")
        target = target[:at] + body + "\n\n" + target[at:]
    TARGET.write_text(target)
    print("Updated embedded Windows reader LLVM")


if __name__ == "__main__":
    main()
