#!/usr/bin/env python3
"""Seeded, structure-aware mutation of Axiom source: the input half of
the compiler fuzzing gate (`scripts/check-fuzz.sh`, R-E1).

WHAT THIS IS. A generator. Given a seed, a count and the corpus (every
tracked `.ax` file, read-only), it writes that many MUTANTS - corpus
files with one to three edits applied - and a manifest naming, for each,
the file it came from and the edits. It runs no compiler: the gate does
that, and holds each mutant to the properties its header states.

DETERMINISM IS THE CONTRACT, so nothing here reads a clock, a hash seed,
the host or the Python version:

  - the PRNG is splitmix64, written out below, not `random`. `random`'s
    stream is stable in practice, but "in practice" is a property of an
    interpreter this file does not control; sixty lines of arithmetic
    are a property of this file.
  - mutant I draws from its OWN stream, `Rng(mix(seed, I))`, so mutant I
    is the same whether it is generated alone (`one`) or as the I-th of
    a thousand, and `--count` never changes an earlier mutant.
  - no set is ever iterated (a set of strings iterates in hash order,
    which `PYTHONHASHSEED` changes per process); the corpus list is
    sorted by code point, not by locale.
  - `digest` is the SHA-256 of the manifest and every mutant's bytes,
    printed by `gen`. Two hosts that print the same digest generated
    the same inputs. The gate generates twice, in two processes with
    two different hash seeds, and requires the digests to agree.

The output is a pure function of (seed, index, corpus bytes). A change
to the corpus - any edit to any tracked `.ax` - changes the mutants, so
"same seed, same mutants" holds per commit, not across commits.

THE MUTATIONS. A small reader (`scan`) finds balanced forms - `( )`,
`{ }`, `[ ]` - atoms, string and char literals, and skips `;` and
nested `#| |#` comments, closely enough to the real lexer that most
edits land on a real syntactic unit and the mutant gets past the reader
to the checker. It is deliberately forgiving: an unmatched closer is an
atom, an unclosed opener runs to the end, so it can re-read its own
output for a second and third edit. See `OPS` for the list and weights.

Subcommands:

  gen  --seed S --count N --corpus LIST --out DIR [--start I]
       writes DIR/mNNNNN.ax and DIR/manifest.tsv, prints
       `digest <hex> identical <n>` (n: mutants no edit changed)
  one  --seed S --index I --corpus LIST --out FILE
       writes mutant I alone (the reproduce path), prints its manifest row
  diff --corpus-root ROOT MANIFEST DIR NAME [--lines N]
       a unified diff of mutant NAME against the file it came from
  json LIST
       LIST names, one per line, files each holding one
       `--diagnostic-format json` stderr; prints `<file><TAB><why>` for
       every malformed one (see `json_ok`) and `checked N`
  human LIST
       the same for human-format `check` stderr: prints `<file><TAB><why>`
       for every report a terminal cannot safely print (see `human_ok`)
       and `checked N`
  selftest
       the PRNG's first outputs, the scanner on fixed text, and the JSON
       and human checkers refusing malformed reports - the generator's
       own canaries
  reduce --cmd CMD FILE OUT
       shrink FILE while `sh -c CMD` (with $FUZZ_INPUT set) still exits
       0; a triage tool for a red run, not used by the gate

LIMITS. Mutation of existing programs explores the neighbourhood of the
corpus, not the language: a crash that needs a construct no corpus file
comes near is not found. Nothing here generates well-typed programs on
purpose, so most mutants are refused by the reader or the checker and
only a minority reach code generation - the gate prints how many.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

MASK = (1 << 64) - 1


class Rng:
    """splitmix64 (Steele, Lea, Flood 2014)."""

    def __init__(self, seed):
        self.s = seed & MASK

    def next(self):
        self.s = (self.s + 0x9E3779B97F4A7C15) & MASK
        z = self.s
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        return z ^ (z >> 31)

    def below(self, n):
        # modulo bias is < 2^-50 for every n used here
        return self.next() % n if n > 0 else 0

    def choice(self, seq):
        return seq[self.below(len(seq))]

    def weighted(self, pairs):
        total = sum(w for _, w in pairs)
        r = self.below(total)
        for item, w in pairs:
            if r < w:
                return item
            r -= w
        return pairs[-1][0]


def mix(seed, index):
    r = Rng((seed * 0x100000001B3) ^ (index * 0xD6E8FEB86659FD93))
    r.next()
    return r.next()


# ---------------------------------------------------------------------
# The reader.

class Node:
    __slots__ = ("start", "end", "kind", "children", "depth")

    def __init__(self, start, end, kind, depth):
        self.start, self.end, self.kind, self.depth = start, end, kind, depth
        self.children = []


OPENERS = {"(": ")", "{": "}", "[": "]"}
CLOSERS = set(")}]")
TOKEN = re.compile(
    r'(?P<ws>\s+)'
    r'|(?P<lc>;[^\n]*)'
    r'|(?P<str>"(?:[^"\\]|\\.)*"?)'
    r"|(?P<chr>'(?:\\.|[^\\\s(\[])')"
    r'|(?P<delim>[()\[\]{}])'
    r'|(?P<atom>[^\s()\[\]{}";]+)',
    re.S)


def skip_block(text, pos):
    """`pos` is just past an opening `#|`; answer the position past its
    nested close, or the end of text (the lexer's rule: unterminated is
    comment to the end)."""
    depth, n = 1, len(text)
    while pos < n and depth > 0:
        if text.startswith("#|", pos):
            depth += 1
            pos += 2
        elif text.startswith("|#", pos):
            depth -= 1
            pos += 2
        else:
            pos += 1
    return pos


def scan(text):
    """Answer (top, nodes): the top-level nodes and every node in
    preorder. Kinds: 'form' (with `.children`), 'atom', 'str', 'chr'."""
    top, nodes, stack = [], [], []
    pos, n = 0, len(text)
    while pos < n:
        if text.startswith("#|", pos):
            pos = skip_block(text, pos + 2)
            continue
        m = TOKEN.match(text, pos)
        if m is None:           # cannot happen: `atom` takes any other byte
            pos += 1
            continue
        kind = m.lastgroup
        end = m.end()
        if kind in ("ws", "lc"):
            pos = end
            continue
        depth = len(stack)
        parent = stack[-1].children if stack else top
        if kind == "delim":
            ch = text[pos]
            if ch in OPENERS:
                node = Node(pos, -1, "form", depth)
                parent.append(node)
                nodes.append(node)
                stack.append(node)
            elif stack:
                stack.pop().end = end
            else:
                node = Node(pos, end, "atom", depth)   # a stray closer
                parent.append(node)
                nodes.append(node)
            pos = end
            continue
        node = Node(pos, end, kind, depth)
        parent.append(node)
        nodes.append(node)
        pos = end
    for node in stack:
        node.end = n
    return top, nodes


def forms(nodes):
    return [x for x in nodes if x.kind == "form"]


def siblings_of(top, nodes):
    """Every list of two or more siblings: the top level and each form's
    children."""
    out = [top] if len(top) >= 2 else []
    out += [x.children for x in nodes if x.kind == "form" and len(x.children) >= 2]
    return out


# ---------------------------------------------------------------------
# The corpus, read lazily: a donor file is scanned the first time it is
# drawn and cached, so a run touches only the files it draws.

class Corpus:
    def __init__(self, root, paths, texts=None):
        self.root = root
        self.paths = sorted(paths)       # code point order, not locale
        self._text = {}
        self._scan = {}
        if texts is not None:            # an in-memory corpus (selftest)
            for i, p in enumerate(self.paths):
                self._text[i] = texts[p]

    def text(self, i):
        if i not in self._text:
            with open(os.path.join(self.root, self.paths[i]), "rb") as f:
                self._text[i] = f.read().decode("utf-8", "surrogateescape")
        return self._text[i]

    def scanned(self, i):
        if i not in self._scan:
            self._scan[i] = scan(self.text(i))
        return self._scan[i]

    def donor_node(self, rng, want=None):
        """A node from a random corpus file: any node, or one of kind
        `want`. Answers its text, or None when the drawn file has none."""
        i = rng.below(len(self.paths))
        _, nodes = self.scanned(i)
        pool = nodes if want is None else [x for x in nodes if x.kind == want]
        if not pool:
            return None
        x = rng.choice(pool)
        return self.text(i)[x.start:x.end]

    def donor_head(self, rng):
        """The head atom of a random form in a random file - which is
        where the keywords are (`fn`, `let`, `match`, `::`, ...)."""
        i = rng.below(len(self.paths))
        _, nodes = self.scanned(i)
        heads = [x.children[0] for x in nodes
                 if x.kind == "form" and x.children and x.children[0].kind == "atom"]
        if not heads:
            return None
        h = rng.choice(heads)
        return self.text(i)[h.start:h.end]


# ---------------------------------------------------------------------
# The mutations. Each takes (rng, text, corpus) and answers
# (new_text, description) or None when it does not apply to this text
# (no string literal to edit, say) - the caller then draws another.

EDGE_INTS = [
    "0", "-0", "1", "-1", "2", "7", "8", "15", "16", "63", "64", "255", "256",
    "65535", "65536", "2147483647", "-2147483648", "4294967295", "4294967296",
    "4611686018427387904", "9223372036854775807", "-9223372036854775808",
    "9223372036854775808", "-9223372036854775809", "18446744073709551615",
    "18446744073709551616", "340282366920938463463374607431768211456",
    "00", "007", "-00", "1_000",
]

ODD_TEXT = [
    "\x00", "\x01", "\x07", "\x08", "\x0b", "\x0c", "\x1b", "\x7f", "\r", "\r\n",
    "\t", " ", "é", "中", "\U0001F600", "﻿", "​",
    " ", "́", "￿",
    # raw bytes that are not UTF-8 (surrogateescape spells a byte as
    # U+DC00 + byte): a lone continuation, an overlong NUL, a truncated
    # three-byte sequence, 0xFF, an encoded surrogate
    "\udc80", "\udcc0\udc80", "\udce2\udc82", "\udcff", "\udced\udca0\udc80",
]

STRING_EDITS = [
    "\\q", "\\", "\\u{110000}", "\\u{D800}", "\\u{}", "\\u{", "\\x41", "\\0",
    "\\n\\t\\r", "\n", "%s%d%n", "{}", "{0}", "\\\"", "\x00", "\udcff",
    "é中\U0001F600",
]

WRAPS = [("(", ")"), ("{", "}"), ("[", "]"), ("(", " )"), ("'(", ")")]

DELIMS = "(){}[]"


def pick_node(rng, nodes, forms_bias=True):
    if forms_bias and rng.below(2) == 0:
        fs = forms(nodes)
        if fs:
            return rng.choice(fs)
    return rng.choice(nodes) if nodes else None


def splice(text, start, end, new):
    return text[:start] + new + text[end:]


def op_delete(rng, text, corpus):
    _, nodes = scan(text)
    x = pick_node(rng, nodes)
    if x is None:
        return None
    return splice(text, x.start, x.end, ""), "delete %s@%d" % (x.kind, x.start)


def op_duplicate(rng, text, corpus):
    _, nodes = scan(text)
    x = pick_node(rng, nodes)
    if x is None:
        return None
    s = text[x.start:x.end]
    return splice(text, x.end, x.end, " " + s), "duplicate %s@%d" % (x.kind, x.start)


def op_swap(rng, text, corpus):
    top, nodes = scan(text)
    groups = siblings_of(top, nodes)
    if not groups:
        return None
    g = rng.choice(groups)
    i = rng.below(len(g))
    j = rng.below(len(g) - 1)
    if j >= i:
        j += 1
    a, b = (g[i], g[j]) if i < j else (g[j], g[i])
    ta, tb = text[a.start:a.end], text[b.start:b.end]
    out = text[:a.start] + tb + text[a.end:b.start] + ta + text[b.end:]
    return out, "swap @%d @%d" % (a.start, b.start)


def op_replace_atom(rng, text, corpus):
    _, nodes = scan(text)
    atoms = [x for x in nodes if x.kind == "atom"]
    if not atoms:
        return None
    x = rng.choice(atoms)
    new = corpus.donor_node(rng, "atom")
    if new is None:
        return None
    return splice(text, x.start, x.end, new), "atom@%d -> %r" % (x.start, new[:40])


def op_replace_head(rng, text, corpus):
    _, nodes = scan(text)
    heads = [x.children[0] for x in nodes
             if x.kind == "form" and x.children and x.children[0].kind == "atom"]
    if not heads:
        return None
    x = rng.choice(heads)
    new = corpus.donor_head(rng)
    if new is None:
        return None
    return splice(text, x.start, x.end, new), "head@%d -> %r" % (x.start, new[:40])


INT_RE = re.compile(r"-?[0-9]+\Z")


def op_edge_int(rng, text, corpus):
    _, nodes = scan(text)
    ints = [x for x in nodes if x.kind == "atom" and INT_RE.match(text, x.start, x.end)]
    if ints:
        x = rng.choice(ints)
    else:
        atoms = [x for x in nodes if x.kind == "atom"]
        if not atoms:
            return None
        x = rng.choice(atoms)
    new = rng.choice(EDGE_INTS)
    return splice(text, x.start, x.end, new), "int@%d -> %s" % (x.start, new)


def op_splice(rng, text, corpus):
    _, nodes = scan(text)
    x = pick_node(rng, nodes)
    if x is None:
        return None
    new = corpus.donor_node(rng, "form" if rng.below(2) else None)
    if new is None:
        return None
    return splice(text, x.start, x.end, new), "splice@%d <- %d bytes" % (x.start, len(new))


def op_drop_delim(rng, text, corpus):
    idx = [i for i, c in enumerate(text) if c in DELIMS]
    if not idx:
        return None
    i = rng.choice(idx)
    return splice(text, i, i + 1, ""), "drop %r@%d" % (text[i], i)


def op_insert_delim(rng, text, corpus):
    _, nodes = scan(text)
    if nodes and rng.below(4):
        x = rng.choice(nodes)
        at = x.start if rng.below(2) else x.end
    else:
        at = rng.below(len(text) + 1)
    d = rng.choice(DELIMS)
    return splice(text, at, at, d), "insert %r@%d" % (d, at)


def op_truncate(rng, text, corpus):
    if not text:
        return None
    at = rng.below(len(text))
    return text[:at], "truncate@%d" % at


def op_odd_bytes(rng, text, corpus):
    at = rng.below(len(text) + 1)
    s = rng.choice(ODD_TEXT)
    return splice(text, at, at, s), "bytes@%d %r" % (at, s)


def op_string(rng, text, corpus):
    _, nodes = scan(text)
    strs = [x for x in nodes if x.kind in ("str", "chr")]
    if not strs:
        return None
    x = rng.choice(strs)
    k = rng.below(4)
    if k == 0 and x.end - x.start >= 2:      # lose the closing quote
        return splice(text, x.end - 1, x.end, ""), "unclose %s@%d" % (x.kind, x.start)
    if k == 1:                               # a long literal
        body = text[x.start + 1:x.end - 1] or "a"
        new = text[x.start] + body * (4096 // len(body) + 1) + text[x.end - 1]
        return splice(text, x.start, x.end, new), "lengthen %s@%d" % (x.kind, x.start)
    e = rng.choice(STRING_EDITS)
    at = x.start + 1 + rng.below(max(1, x.end - x.start - 1))
    return splice(text, at, at, e), "escape %s@%d %r" % (x.kind, x.start, e)


def op_empty(rng, text, corpus):
    _, nodes = scan(text)
    fs = forms(nodes)
    if not fs:
        return None
    x = rng.choice(fs)
    o = text[x.start]
    return splice(text, x.start, x.end, o + OPENERS.get(o, ")")), "empty@%d" % x.start


def op_wrap(rng, text, corpus):
    _, nodes = scan(text)
    x = pick_node(rng, nodes)
    if x is None:
        return None
    o, c = rng.choice(WRAPS)
    out = text[:x.start] + o + text[x.start:x.end] + c + text[x.end:]
    return out, "wrap %r@%d" % (o, x.start)


def op_deep(rng, text, corpus):
    """Nest a node K levels deeper, K chosen around the parser's limit
    (`parseMaxDepth`, 1024, counts delimiters from the top) and well
    past it."""
    _, nodes = scan(text)
    x = pick_node(rng, nodes)
    if x is None:
        return None
    target = rng.choice([1000, 1022, 1023, 1024, 1025, 1100, 5000])
    k = max(1, target - x.depth)
    o, c = rng.choice(WRAPS[:3])
    out = text[:x.start] + o * k + text[x.start:x.end] + c * k + text[x.end:]
    return out, "deep %d %r@%d" % (k, o, x.start)


def op_long(rng, text, corpus):
    """A form's last child repeated N times: a long application spine,
    a long block, a long binding list - depth the parser does not count
    but a recursive walk over the result might.

    N stops at 5,000 because compile time is SUPERLINEAR in the
    bindings of one `let` (measured 2026-09-27, emit-llvm: 4,000 in
    0.85s, 8,000 in 4.7s, 16,000 in 24s), so at 20,000 the gate's
    deadline would be measuring that known cliff - recorded in
    CONTRIBUTING.md - and not a hang.

    And the edit stops at 100,000 bytes, where it stopped at 1,000,000:
    `llc -O0` is itself superlinear in one function's basic blocks. A
    `println` branch repeated in an `if` chain measured 1,000 branches
    at 4 s of `llc` and 2,000 at 49 s, and the `--long` mutant that
    repeated one 4,878 times (180,538 blocks, 60 MB of IR) was still in
    `llc` after ten minutes - a size the gate's deadline cannot judge,
    so it read as a hang (2026-09-28)."""
    _, nodes = scan(text)
    fs = [x for x in forms(nodes) if x.children]
    if not fs:
        return None
    x = rng.choice(fs)
    ch = x.children[-1]
    n = rng.choice([200, 1000, 5000])
    s = " " + text[ch.start:ch.end]
    if len(s) * n > 100000:
        n = max(2, 100000 // len(s))
    return splice(text, ch.end, ch.end, s * n), "long %dx@%d" % (n, ch.start)


# name, function, weight
OPS = [
    ("delete", op_delete, 10),
    ("duplicate", op_duplicate, 8),
    ("swap", op_swap, 8),
    ("atom", op_replace_atom, 12),
    ("head", op_replace_head, 10),
    ("int", op_edge_int, 8),
    ("splice", op_splice, 10),
    ("drop", op_drop_delim, 4),
    ("insert", op_insert_delim, 4),
    ("truncate", op_truncate, 3),
    ("bytes", op_odd_bytes, 5),
    ("string", op_string, 5),
    ("empty", op_empty, 5),
    ("wrap", op_wrap, 5),
    ("deep", op_deep, 2),
    ("long", op_long, 2),
]


def mutate(seed, index, corpus, ops=None):
    """Mutant `index` of `seed`: (source path, text, [descriptions])."""
    rng = Rng(mix(seed, index))
    src = rng.below(len(corpus.paths))
    orig = corpus.text(src)
    text = orig
    table = [(o, w) for o in OPS for w in [o[2]] if ops is None or o[0] in ops]
    nops = rng.weighted([(1, 6), (2, 3), (3, 1)])
    done = []
    tries = 0
    while (len(done) < nops or text == orig) and tries < 40:
        tries += 1
        name, fn, _ = rng.weighted(table)
        r = fn(rng, text, corpus)
        if r is None:
            continue
        text, what = r
        done.append(name + ": " + what)
    return corpus.paths[src], text, done


def encode(text):
    return text.encode("utf-8", "surrogateescape")


def read_corpus_list(path, root):
    with open(path, encoding="utf-8") as f:
        paths = [ln.rstrip("\n") for ln in f if ln.strip()]
    return Corpus(root, paths)


def manifest_row(name, src, ops):
    # tabs and newlines cannot appear in a description (repr escapes them)
    return "%s\t%s\t%s" % (name, src, " | ".join(ops))


# ---------------------------------------------------------------------
# Subcommands.

def cmd_gen(args):
    corpus = read_corpus_list(args["--corpus"], args.get("--root", "."))
    seed, count = int(args["--seed"]), int(args["--count"])
    start = int(args.get("--start", "0"))
    out = args["--out"]
    os.makedirs(out, exist_ok=True)
    h = hashlib.sha256()
    rows = []
    identical = 0
    for i in range(start, start + count):
        name = "m%05d" % i
        src, text, ops = mutate(seed, i, corpus)
        identical += text == corpus.text(corpus.paths.index(src))
        data = encode(text)
        with open(os.path.join(out, name + ".ax"), "wb") as f:
            f.write(data)
        row = manifest_row(name, src, ops)
        rows.append(row)
        h.update(row.encode("utf-8", "surrogateescape") + b"\n")
        h.update(hashlib.sha256(data).digest())
    with open(os.path.join(out, "manifest.tsv"), "w", encoding="utf-8",
              errors="surrogateescape") as f:
        f.write("\n".join(rows) + "\n")
    print("digest %s identical %d" % (h.hexdigest(), identical))
    return 0


def cmd_one(args):
    corpus = read_corpus_list(args["--corpus"], args.get("--root", "."))
    seed, i = int(args["--seed"]), int(args["--index"])
    src, text, ops = mutate(seed, i, corpus)
    with open(args["--out"], "wb") as f:
        f.write(encode(text))
    print(manifest_row("m%05d" % i, src, ops))
    return 0


def cmd_diff(args, pos):
    import difflib
    manifest, mdir, name = pos
    root = args.get("--corpus-root", ".")
    limit = int(args.get("--lines", "60"))
    src = None
    with open(manifest, encoding="utf-8", errors="surrogateescape") as f:
        for ln in f:
            parts = ln.rstrip("\n").split("\t")
            if parts[0] == name:
                src = parts[1]
    if src is None:
        print("no %s in %s" % (name, manifest))
        return 1
    with open(os.path.join(root, src), "rb") as f:
        a = f.read().decode("utf-8", "surrogateescape").splitlines(True)
    with open(os.path.join(mdir, name + ".ax"), "rb") as f:
        b = f.read().decode("utf-8", "surrogateescape").splitlines(True)
    lines = list(difflib.unified_diff(a, b, src, name + ".ax", n=2))
    for ln in lines[:limit]:
        # show control and non-UTF-8 bytes rather than emitting them
        s = ln.rstrip("\n")
        print(ascii(s)[1:-1] if any(ord(c) < 32 and c != "\t" or 0xDC80 <= ord(c) <= 0xDCFF
                                    or ord(c) > 126 for c in s) else s)
    if len(lines) > limit:
        print("... (%d more diff lines)" % (len(lines) - limit))
    return 0


CODE_RE = re.compile(r"AX[0-9]{4}\Z")
# `renderFailTrailer` (self_host/render.ax): printed after a failed
# compilation "in every format", stage0's behaviour, so it is part of
# the JSON-mode contract rather than a stray line - but only as the
# LAST line, and only spelled exactly so.
TRAILER_RE = re.compile(r"compilation failed due to [0-9]+ previous errors?\Z")


def span_why(sp):
    """None when `sp` is a well-formed span object, else the reason."""
    if not isinstance(sp, dict):
        return "is not an object"
    pts = []
    for k in ("start", "end"):
        p = sp.get(k)
        if not (isinstance(p, dict) and type(p.get("line")) is int
                and type(p.get("col")) is int):
            return ".%s is not {line, col}" % k
        if p["line"] < 1 or p["col"] < 1:
            return ".%s is %d:%d, not 1-based" % (k, p["line"], p["col"])
        pts.append((p["line"], p["col"]))
    if pts[0] > pts[1]:
        return " starts at %d:%d, after its end %d:%d" % (pts[0] + pts[1])
    cs, ce = sp.get("char_start"), sp.get("char_end")
    if type(cs) is not int or type(ce) is not int:
        return ".char_start/.char_end are not integers"
    if not 0 <= cs <= ce:
        return " has char offsets %d..%d" % (cs, ce)
    return None


def json_ok(data):
    """None when `data` (the stderr of one `--diagnostic-format json`
    refusal) is well formed, else the reason.

    Well formed is the contract as docs/diagnostics.md ("JSON Lines")
    and `renderDiagJson` state it: every non-empty line but a final
    `renderFailTrailer` line is one JSON object; `severity`, `code`,
    `slug`, `message` and `file` are strings; `related`, `notes`, `help`
    and `expansion` are arrays; `span` is present only when the
    diagnostic has one and `label` only when it has one (a consumer
    tells "no label" from "empty label"), and a span is 1-based and
    does not end before it starts; a related entry is an object with a
    `label` and an optional span. At least one line is an error whose
    code is `AXnnnn` - the JSON spelling of the human `error[AXnnnn]`."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as e:
        return "not UTF-8: %s" % e
    errors = 0
    lines = [ln for ln in text.split("\n") if ln.strip()]
    if lines and TRAILER_RE.match(lines[-1]):
        lines = lines[:-1]
    if not lines:
        return "no diagnostic lines"
    for n, ln in enumerate(lines, 1):
        try:
            d = json.loads(ln)
        except ValueError as e:
            return "line %d is not JSON (%s): %s" % (n, e, ln[:120])
        if not isinstance(d, dict):
            return "line %d is not an object" % n
        for k, t in (("severity", str), ("code", str), ("slug", str),
                     ("message", str), ("file", str), ("related", list),
                     ("notes", list), ("help", list), ("expansion", list)):
            if not isinstance(d.get(k), t):
                return "line %d: key %r missing or not %s" % (n, k, t.__name__)
        if "span" in d:
            why = span_why(d["span"])
            if why:
                return "line %d: span%s" % (n, why)
        if "label" in d and not isinstance(d["label"], str):
            return "line %d: label is not a string" % n
        for r in d["related"]:
            if not (isinstance(r, dict) and isinstance(r.get("label"), str)):
                return "line %d: a related entry is not {label, ...}" % n
            if "span" in r:
                why = span_why(r["span"])
                if why:
                    return "line %d: a related span%s" % (n, why)
        for k in ("notes", "help"):
            if not all(isinstance(s, str) for s in d[k]):
                return "line %d: %s holds a non-string" % (n, k)
        if d["severity"] == "error":
            if not CODE_RE.match(d["code"]):
                return "line %d: error code %r is not AXnnnn" % (n, d["code"])
            errors += 1
    if errors == 0:
        return "no line has severity error"
    return None


def cmd_json(pos):
    """`json LIST`: LIST names one report file per line. Prints
    `<file><TAB><reason>` for each malformed report and `checked N` last;
    answers 1 when any was malformed."""
    bad = n = 0
    with open(pos[0], encoding="utf-8") as f:
        files = [ln.rstrip("\n") for ln in f if ln.strip()]
    for p in files:
        with open(p, "rb") as f:
            why = json_ok(f.read())
        n += 1
        if why is not None:
            print("%s\t%s" % (p, why.replace("\t", " ").replace("\n", " ")))
            bad += 1
    print("checked %d" % n)
    return 1 if bad else 0


# One SGR colour sequence - the only escape the human renderer writes.
# Its parameters must be one of self_host/style.ax's palette entries
# (the render gate's check 5 reads the same table), or `0`, the reset:
# a source file that smuggles `ESC [ 31 m` into a quoted line writes a
# sequence of exactly this SHAPE, so the shape alone would excuse it.
SGR_RE = re.compile(rb"\x1b\[([0-9;]*)m")


def style_palette(root):
    """The SGR parameter strings self_host/style.ax declares, and `0`."""
    with open(os.path.join(root, "self_host", "style.ax"), encoding="utf-8") as f:
        pal = set(re.findall(r'"([0-9;]+)"', f.read()))
    pal.add("0")
    return pal


def human_ok(data, palette):
    """None when `data` (the stderr of one human-format `check`) is safe
    to print to a terminal, else the reason.

    Safe is: well-formed UTF-8, and no control byte but the newline once
    the colour sequences are taken out. A raw ESC lets a source file
    write escape sequences - a colour, a cursor move, a window title -
    into the report; a NUL, a backspace or a carriage return hides or
    moves what the caret row points at; a tab is drawn by the renderer
    as spaces wherever it has a column to keep. The message surfaces
    have escaped control bytes since 2026-08-16; the QUOTED SOURCE LINE
    echoed them raw until 2026-09-27 (`dispUnitText` in render.ax)."""
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as e:
        return "not UTF-8: %s" % e
    for m in SGR_RE.finditer(data):
        if m.group(1).decode("ascii") not in palette:
            return "an SGR sequence ESC[%sm on report line %d that style.ax does not declare" % (
                m.group(1).decode("ascii"), data[:m.start()].count(b"\n") + 1)
    plain = SGR_RE.sub(b"", data)
    for i, b in enumerate(plain):
        if (b < 32 and b != 10) or b == 127:
            return "raw control byte 0x%02X on report line %d" % (b, plain[:i].count(b"\n") + 1)
    return None


def cmd_human(pos):
    """`human LIST`: as `json`, for human-format reports and `human_ok`,
    against the palette of the tree this file is in."""
    palette = style_palette(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    bad = n = 0
    with open(pos[0], encoding="utf-8") as f:
        files = [ln.rstrip("\n") for ln in f if ln.strip()]
    for p in files:
        with open(p, "rb") as f:
            why = human_ok(f.read(), palette)
        n += 1
        if why is not None:
            print("%s\t%s" % (p, why.replace("\t", " ").replace("\n", " ")))
            bad += 1
    print("checked %d" % n)
    return 1 if bad else 0


# A corpus that is not the tree, and the digest of 200 mutants of it at
# seed 1. The tree's own mutants move with every edit to any `.ax`, so
# no digest of them can be pinned; this one can, and pinning it is what
# makes "the same seed gives the same mutants on every host" a CHECK on
# each CI leg rather than a property asserted by one host about itself.
# A deliberate change to the mutations changes it: re-run
# `fuzz.py selftest`, read the digest it reports, and update this line
# in the same commit.
PINNED_CORPUS = {
    "a.ax": '(import IO)\n\n(:: main Int)\n;@axiom:effect(io)\n(fn (main)\n'
            '  {\n    (println "hi \\n")\n    (let ((x 42) (y -7)) (+ x y))\n  })\n',
    "b.ax": '#| a #| nested |# comment |#\n(data Shape (Circle Int) (Sq Int))\n'
            '(:: area (-> Shape Int))\n(fn (area s)\n  (match s\n'
            '    ((Circle r) (* 3 (* r r)))\n    ((Sq w) (* w w))))\n',
    "c.ax": "(struct P (x : Int) (y : Int))\n(macro (twice e) (+ e e))\n"
            "(fn (f p) [(P-x p) 'a' '\\n' (twice 9223372036854775807)])\n",
}
PINNED_DIGEST = "7234a79dcc9f24c94e84feeab5518c4fb9e1af1095db92798d1264cdc9f902fd"


def pinned_digest():
    corpus = Corpus(".", list(PINNED_CORPUS), PINNED_CORPUS)
    h = hashlib.sha256()
    for i in range(200):
        src, text, ops = mutate(1, i, corpus)
        h.update(manifest_row("m%05d" % i, src, ops).encode("utf-8", "surrogateescape"))
        h.update(hashlib.sha256(encode(text)).digest())
    return h.hexdigest()


def cmd_selftest():
    # the PRNG against splitmix64's published first outputs for seed 0
    r = Rng(0)
    want = [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F]
    got = [r.next() for _ in want]
    if got != want:
        print("splitmix64 drifted: %s" % [hex(g) for g in got])
        return 1
    d = pinned_digest()
    if d != PINNED_DIGEST:
        print("the generator's output for the pinned corpus moved: %s, pinned %s"
              % (d, PINNED_DIGEST))
        print("(a deliberate change to the mutations updates PINNED_DIGEST; "
              "anything else is a determinism defect)")
        return 1
    top, nodes = scan('(a "b)" #| ( |# [c {d}]) \'x\' ; )\n)')
    kinds = [x.kind for x in nodes]
    if kinds != ["form", "atom", "str", "form", "atom", "form", "atom", "chr", "atom"]:
        print("scanner drifted: %s" % kinds)
        return 1
    good = (b'{"severity":"error","code":"AX3001","slug":"x","message":"m",'
            b'"file":"f","span":{"start":{"line":1,"col":1},"end":{"line":1,"col":2},'
            b'"char_start":0,"char_end":1},"label":"l","related":[],"notes":[],'
            b'"help":[],"expansion":[]}\n')
    trailer = b"compilation failed due to 1 previous error\n"
    spanless = (b'{"severity":"error","code":"AX4001","slug":"x","message":"m",'
                b'"file":"f","related":[{"label":"*"}],"notes":[],"help":[],'
                b'"expansion":[]}\n')
    accepted = (good, good + trailer, spanless + trailer)
    for ok in accepted:
        if json_ok(ok) is not None:
            print("the JSON checker refused a well-formed report: %s" % json_ok(ok))
            return 1
    refused = (good[:-5] + b"\n", b"", trailer, good.replace(b"AX3001", b"AX30"),
               good.replace(b'"severity":"error"', b'"severity":"warning"'),
               good.replace(b'"line":1,', b'"line":"1",', 1), b"\xff\n",
               trailer + good, good + b"compilation failed\n",
               good.replace(b'"line":1,"col":2', b'"line":0,"col":2'),
               good.replace(b'"char_start":0', b'"char_start":5'),
               spanless.replace(b'{"label":"*"}', b'"*"'))
    for broken in refused:
        if json_ok(broken) is None:
            print("the JSON checker accepted a malformed report: %r" % broken[:80])
            return 1
    h_accepted = (b"", b"error[AX3001]: m\n", b"\x1b[1;31merror\x1b[0m: \xe4\xb8\xad \\u{1}\n",
                  b"2 | (s \"\xe2\x90\x9b[31m\")\n")
    h_palette = {"0", "1", "1;31", "1;34"}
    h_refused = (b"\x1b[31mred\x1b[0m\n", b"a\x00b\n", b"\x1b]0;title\x07\n", b"\x1b[31m\x1b[2J\x1b[H\n", b"\xe4\n",
                 b"\xed\xa0\x80\n", b"a\rb\n", b"a\tb\n", b"a\x7fb\n", b"\x1b\n")
    for ok in h_accepted:
        if human_ok(ok, h_palette) is not None:
            print("the human checker refused a safe report: %s" % human_ok(ok, h_palette))
            return 1
    for broken in h_refused:
        if human_ok(broken, h_palette) is None:
            print("the human checker accepted an unsafe report: %r" % broken[:80])
            return 1
    print("selftest: splitmix64, the pinned-corpus digest %s..., the scanner, "
          "the JSON checker (%d accepted, %d refused), the human checker "
          "(%d accepted, %d refused)"
          % (d[:12], len(accepted), len(refused), len(h_accepted), len(h_refused)))
    return 0


def cmd_reduce(args, pos):
    """Greedy reduction: drop top-level forms, then any form, then lines,
    then single characters, keeping each cut while CMD still exits 0."""
    src, out = pos
    cmd = args["--cmd"]
    with open(src, "rb") as f:
        text = f.read().decode("utf-8", "surrogateescape")

    def holds(t):
        with open(out, "wb") as f:
            f.write(encode(t))
        env = dict(os.environ, FUZZ_INPUT=out)
        return subprocess.run(["sh", "-c", cmd], env=env,
                              stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0

    if not holds(text):
        print("the predicate does not hold on the input")
        return 1
    changed = True
    while changed:
        changed = False
        _, nodes = scan(text)
        for x in sorted(nodes, key=lambda x: -(x.end - x.start)):
            if x.end > len(text):
                continue
            t = text[:x.start] + text[x.end:]
            if t != text and holds(t):
                text, changed = t, True
                break
        if changed:
            continue
        lines = text.split("\n")
        for i in range(len(lines)):
            t = "\n".join(lines[:i] + lines[i + 1:])
            if holds(t):
                text, changed = t, True
                break
        if changed:
            continue
        for i in range(len(text)):
            t = text[:i] + text[i + 1:]
            if holds(t):
                text, changed = t, True
                break
    holds(text)
    print("reduced to %d bytes: %s" % (len(encode(text)), out))
    return 0


def parse_args(argv):
    args, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--"):
            args[a] = argv[i + 1]
            i += 2
        else:
            pos.append(a)
            i += 1
    return args, pos


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    args, pos = parse_args(rest)
    if cmd == "gen":
        return cmd_gen(args)
    if cmd == "one":
        return cmd_one(args)
    if cmd == "diff":
        return cmd_diff(args, pos)
    if cmd == "json":
        return cmd_json(pos)
    if cmd == "human":
        return cmd_human(pos)
    if cmd == "selftest":
        return cmd_selftest()
    if cmd == "reduce":
        return cmd_reduce(args, pos)
    print("unknown subcommand %r" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
