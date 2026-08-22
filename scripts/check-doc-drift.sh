#!/usr/bin/env bash
# ---------------------------------------------------------------------
# The normative documents drift because they are maintained by hand.
#
# Nine claims in README.md and docs/reference.md were measurably false
# on 2026-08-10 - a benchmark ratio corrected in another file of the
# same repository, a file count seven versions stale, "No LSP yet"
# forty lines below the row that lists the LSP, and four descriptions
# of behaviour the compiler had never implemented. Every one of them is
# the kind of claim a program can check, and correcting them by hand is
# a treadmill: seven stale file counts have been fixed one at a time
# across this project's history.
#
# So this gate is the anti-drift rule the CLI already has - every name
# in the accept-chain must appear in `--help` - applied to the docs.
#
#   1  THE DIAGNOSTIC REGISTRY, BOTH WAYS. Every code with a
#      construction site outside explain.ax is listed by
#      `explain --list`, and every listed code has a construction site.
#      It is 47/47 today; this line said 39/39 until 2026-08-16, and
#      it is the kind of number this gate exists to stop anyone
#      writing by hand. `check-tools-selfhost.sh` already checks
#      emitted -> listed, which is weaker in the direction that
#      matters: a code CONSTRUCTED but never reached by a corpus
#      fixture escapes it, and AX4001 sat in the table with no
#      construction site for months.
#
#   2  EVERY COUNT IS RECOMPUTED. A claim whose phrase this gate
#      cannot find is a FAILURE, not a skip - a reworded sentence must
#      not silently stop being checked, which is this repository's
#      standing rule about a sweep that reads fewer files than it
#      should.
#
#   3  EVERY **Complete** ROW NAMES A FIXTURE, and the fixture exists.
#      This is the cheapest possible implementation of the
#      corpus-is-the-spec law: it forces the DOCUMENTED surface, not
#      the tree, to define coverage. Three rows named one when this
#      was written; fourteen did not, and two of those fourteen -
#      polymorphic signatures and type aliases - were describing
#      behaviour that did not exist.
#
#   4  EVERY FIXTURE A COMMENT NAMES EXISTS. In the docs; in the
#      SOURCES too, which is where this repository writes most of them,
#      because every refusal names the fixture that pins it; and in
#      both spellings, the `tests/`-prefixed path and the bare
#      `NNN-name.ext` a comment reaches for when the number makes the
#      directory obvious. All three halves were added after a fixture
#      was deleted and its four surviving mentions failed nothing.
#
#   5  EVERY DIAGNOSTIC THE README SHOWCASES IS RE-RENDERED. The
#      "Error Messages" section showed a box-drawn `╭─[err.ax:3:20]`
#      frame with a `Help:` footer, and an AXDL line missing its primary
#      label. Neither had been the compiler's output since the Rust
#      implementation was replaced: the self-hosted renderer is
#      rustc-flavored, elides the lines between two spans with `...`,
#      and prints the machine-applicable replacement after `~>`. A
#      reader arrived expecting the wrong thing about the one surface
#      they meet first. So the showcase is now source plus output, both
#      marked with `<!-- doc-gate:source|render -->`, and this gate
#      compiles the source and diffs the output. Documentation of what a
#      program prints is a golden test with worse ergonomics; this gives
#      it the ergonomics.
# ---------------------------------------------------------------------
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init --no-stdlib
failed=0

gate_build_axc axc

# ---------------------------------------------------------------
# 1. the diagnostic registry, both directions
# ---------------------------------------------------------------
echo "== registry: constructed <-> listed =="
# Comments are stripped first. Without that this counts a code
# MENTIONED in prose - and these files quote codes in prose constantly -
# so a section explaining `AX9999` would fail the gate as an unexplained
# construction site. A code appears before any `;` on its own line at
# every real construction site, so truncating at the first `;` keeps
# every one of them.
constructed="$(sed 's/;.*$//' self_host/*.ax | grep -ohE '"AX[0-9]{4}"' | tr -d '"' | sort -u)"
listed="$("$axc" explain --list 2>/dev/null | grep -oE 'AX[0-9]{4}' | sort -u)"
nc="$(printf '%s\n' "$constructed" | grep -c .)"
nl="$(printf '%s\n' "$listed" | grep -c .)"
if (( nc < 45 )); then
  echo "FAIL: only $nc constructed codes found; the floor is 45 (47 today; the grep stopped matching)"
  failed=$((failed+1))
fi
orphan="$(comm -23 <(printf '%s\n' "$constructed") <(printf '%s\n' "$listed") | tr '\n' ' ')"
unreach="$(comm -13 <(printf '%s\n' "$constructed") <(printf '%s\n' "$listed") | tr '\n' ' ')"
if [[ -n "${orphan// /}" ]]; then
  echo "FAIL registry: constructed but not explained: $orphan"; failed=$((failed+1))
fi
if [[ -n "${unreach// /}" ]]; then
  echo "FAIL registry: explained but never constructed: $unreach"; failed=$((failed+1))
fi
[[ -z "${orphan// /}${unreach// /}" ]] && echo "ok   $nc constructed, $nl explained, sets equal"

# ---------------------------------------------------------------
# 2, 3, 4, 5 - the documents themselves
# ---------------------------------------------------------------
# The prose documents come from `gate_prose_docs`, so this gate,
# `check-tree-sitter.sh` and `check-tools-selfhost.sh` sweep one set
# instead of three hand-written copies that had already diverged.
python3 - "$repo_root" "$axc" $(gate_prose_docs) <<'PY'
import os, re, sys, glob, shutil, subprocess, tempfile
root, axc = sys.argv[1], sys.argv[2]
PROSE_DOCS = sys.argv[3:]
os.chdir(root)
bad = 0
readme = open("README.md", encoding="utf-8").read()

def claim(label, pattern, actual):
    """A numeric claim in the prose, recomputed. A pattern that no
    longer matches is a failure: the sentence was reworded and the
    check quietly stopped applying, which reads exactly like success."""
    global bad
    m = re.search(pattern, readme)
    if not m:
        print(f"FAIL counts: the claim about {label} is not where this gate looks "
              f"(pattern {pattern!r}) - reword the gate with the sentence")
        bad += 1
        return
    stated = int(m.group(1))
    if stated != actual:
        print(f"FAIL counts: README says {stated} {label}, measured {actual}")
        bad += 1
    else:
        print(f"ok   {label}: {actual}")

ax_files = len([p for p in glob.glob("**/*.ax", recursive=True)])
corpus_cases = sum(
    sum(1 for line in open(p, encoding="utf-8") if line.startswith("==="))
    for p in glob.glob("tree-sitter-axiom/test/corpus/*.txt")) // 2

print("== counts: every number the README states is recomputed ==")
claim("`.ax` files in the repo", r"gated against all (\d+) `\.ax` files", ax_files)
claim("tree-shape corpus cases", r"(\d+)-case tree-shape corpus", corpus_cases)

print("== status table: every **Complete** row names a fixture that exists ==")
rows = [l for l in readme.splitlines() if l.startswith("| ") and l.count("|") >= 4]
complete = [r for r in rows if "**Complete**" in r]
if len(complete) < 15:
    print(f"FAIL status: only {len(complete)} **Complete** rows found; the floor is 15 "
          f"(the table moved or the parse broke)")
    bad += 1
for r in complete:
    name = r.split("|")[1].strip()
    paths = re.findall(r"tests/[\w./-]+\.(?:ax|axbad)", r)
    if not paths:
        print(f"FAIL status: **Complete** row {name!r} names no fixture")
        bad += 1
        continue
    for p in paths:
        if not os.path.exists(p):
            print(f"FAIL status: row {name!r} names {p}, which does not exist")
            bad += 1

print("== every tests/ path named in the docs exists ==")
named = set()
# docs/self-hosting.md was NOT in this list, and the omission bit
# immediately: a commit landed three sections naming three fixtures and
# only one of them existed, and this gate passed. It is the document
# that names the most fixtures, because every section ends by saying
# what pins it.
for doc in PROSE_DOCS:
    # The extension alternation needs the boundary: without it
    # `tests/fmt/parity/170-empty-tuple.axp` matched as `...ax` and was
    # reported missing, which is a gate finding its own bug and calling
    # it drift. Caught on this gate's first run.
    named |= set(re.findall(r"tests/[\w./-]+\.(?:axbad|axp|ax|py|sh|out|golden)(?![\w])",
                            open(doc, encoding="utf-8").read()))
if len(named) < 185:
    print(f"FAIL paths: only {len(named)} tests/ paths named across the docs; floor is 185")
    bad += 1
missing = sorted(p for p in named if not os.path.exists(p))
if missing:
    for p in missing:
        print(f"FAIL paths: the docs name {p}, which does not exist")
    bad += len(missing)
else:
    print(f"ok   all {len(named)} tests/ paths named in the docs exist")

# The same check over SOURCE and FIXTURE comments, which this gate did
# not reach and which dangle exactly as readily. Found on 2026-08-16:
# retiring a diagnostic deleted a fixture under `tests/diagnostics/`
# and left two comments pointing at it - one in `self_host/expand.ax`
# explaining the retirement, one in the fixture that replaced it - and
# nothing failed, because both live outside `docs/`. A comment naming a
# file that is not there is drift whatever file the comment is in, and
# these are the comments this repository writes most, because every
# refusal names the fixture that pins it.
#
# This check found its own author on its first run, twice: the sentence
# above originally spelled the deleted path out, and a sibling script
# spells a message template the same way. Both are why the placeholder
# list below exists and why this paragraph does not name a file.
#
# Scripts are included: three of them name `.axp` cases, which is how
# the extension-boundary trap above was found in the first place.
print("== every tests/ path named in the sources exists ==")
src_named = {}
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs
               if d not in (".git", "target", "node_modules", ".axiom-bin")]
    for fn in files:
        if not fn.endswith((".ax", ".sh", ".py")):
            continue
        path = os.path.join(root, fn).lstrip("./")
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for p in re.findall(r"tests/[\w./-]+\.(?:axbad|axp|ax|py|sh|out|golden|axdl|human|json)(?![\w])",
                            text):
            # Every naming file, not the first: a deleted fixture is
            # named by as many comments as explained it, and a report
            # that stops at one is a gate you have to run four times.
            src_named.setdefault(p, []).append(path)
# Placeholders rather than paths: two message templates with the case
# name spliced in at run time, and the REPL's own `:load` example.
for placeholder in ("tests/diagnostics/NAME.human",
                    "tests/stdlib/NAME.out",
                    "tests/selfhost/x.ax"):
    src_named.pop(placeholder, None)
if len(src_named) < 64:
    print(f"FAIL paths: only {len(src_named)} tests/ paths named across the sources; floor is 64")
    bad += 1
src_missing = sorted((p, fs) for p, fs in src_named.items() if not os.path.exists(p))
if src_missing:
    for p, fs in src_missing:
        for f in sorted(set(fs)):
            print(f"FAIL paths: {f} names {p}, which does not exist")
    bad += len(src_missing)
else:
    print(f"ok   all {len(src_named)} tests/ paths named in the sources exist")

# The SAME class again, in the spelling this repository actually writes
# most: a bare `NNN-name.ext`, no directory, because the directory is
# obvious from the number. Measured on 2026-08-16 the bare spelling
# outnumbers the path spelling in the sources, 86 distinct names to 68 -
# and every one of the two checks above was blind to it.
#
# It found four dangling names on its first run, in four different
# files, and only one of them was the retirement that prompted it.
# The other three each spelled an `.axbad` case `.ax` - including the
# comment in `check-diagnostics.sh` whose whole subject is that such a
# file CANNOT be spelled `.ax`, because check-fmt and check-tree-sitter
# sweep every `*.ax` in the repository and would judge it. So the
# extension is not incidental here: it is the fact the fixture exists
# to record, and a comment that gets it wrong points at nothing while
# reading as though it points at the case.
#
# Resolution is by BASENAME, against an index of everything under
# `tests/`, because that is what a reader does with a bare name.
print("== every fixture named by bare filename exists ==")
tests_index = set()
for root, dirs, files in os.walk("tests"):
    tests_index.update(files)
bare_pat = re.compile(
    r"(?<![\w/.-])(\d{3}-[\w-]+\.(?:axbad|axp|ax|py|sh|out|golden|axdl|human|json))(?![\w])")
bare_named = {}
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs
               if d not in (".git", "target", "node_modules", ".axiom-bin")]
    for fn in files:
        if not fn.endswith((".ax", ".sh", ".py", ".md")):
            continue
        path = os.path.join(root, fn).lstrip("./")
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for p in bare_pat.findall(text):
            bare_named.setdefault(p, []).append(path)
if len(bare_named) < 82:
    print(f"FAIL paths: only {len(bare_named)} bare fixture names found; floor is 82")
    bad += 1
bare_missing = sorted((p, fs) for p, fs in bare_named.items() if p not in tests_index)
if bare_missing:
    for p, fs in bare_missing:
        for f in sorted(set(fs)):
            print(f"FAIL paths: {f} names {p}, which is not a file under tests/")
    bad += len(bare_missing)
else:
    print(f"ok   all {len(bare_named)} bare fixture names resolve under tests/")

print("== the diagnostics the README showcases are re-rendered and diffed ==")
# Every diagnostic block in the README is a `<!-- doc-gate:render NAME
# FMT -->` marker over a fence, and the file it came from is a
# `<!-- doc-gate:source NAME -->` marker over a fence. Markdown does not
# render an HTML comment, so the prose stays clean and the gate has a
# handle. Everything the compiler prints goes to stderr, so stdout is
# not consulted: a diagnostic that started arriving on stdout is drift
# the same as a reworded label.
ANSI = re.compile(r"\x1b\[[0-9;]*m")
marked = re.findall(
    r"<!-- doc-gate:(source|render) ([\w.-]+)(?: +(\w+))? -->\n```[a-z]*[^\n]*\n(.*?)^```",
    readme, re.S | re.M)
sources = {name: body for kind, name, _fmt, body in marked if kind == "source"}
renders = [(name, fmt, body) for kind, name, fmt, body in marked if kind == "render"]
if len(renders) < 4:
    print(f"FAIL showcase: only {len(renders)} rendered blocks are marked; the floor is 4 "
          f"(the markers were dropped and this check silently stopped applying)")
    bad += 1
work = tempfile.mkdtemp()
try:
    for name, body in sources.items():
        with open(os.path.join(work, name), "w", encoding="utf-8") as fh:
            fh.write(body)
    for name, fmt, expected in renders:
        if name not in sources:
            print(f"FAIL showcase: the {fmt} block for {name} has no doc-gate:source block "
                  f"- the README shows output nobody can reproduce")
            bad += 1
            continue
        # cwd is the temp dir so the compiler reports the bare filename,
        # which is what the README shows.
        proc = subprocess.run([axc, "check", f"--diagnostic-format={fmt}", name],
                              cwd=work, capture_output=True, text=True)
        actual = ANSI.sub("", proc.stderr)
        if actual.strip("\n") != expected.strip("\n"):
            print(f"FAIL showcase: the {fmt} block for {name} is not what the compiler prints")
            print("  --- README says ---")
            for line in expected.rstrip("\n").splitlines():
                print(f"  | {line}")
            print("  --- compiler prints ---")
            for line in actual.rstrip("\n").splitlines():
                print(f"  | {line}")
            bad += 1
        else:
            print(f"ok   {name} ({fmt}) renders exactly as documented")
finally:
    shutil.rmtree(work, ignore_errors=True)

sys.exit(1 if bad else 0)
PY
[[ $? -eq 0 ]] || failed=$((failed+1))

echo
if (( failed )); then
  echo "check-doc-drift: $failed section(s) failed"
  exit 1
fi
echo "check-doc-drift: registry, counts, status rows, fixture paths and the"
echo "                 diagnostic showcase all agree with the tree"
