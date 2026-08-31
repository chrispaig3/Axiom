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
#      It is 51/51 today - and the count is stated here only because a
#      reader wants a scale; the gate computes it, which is the whole
#      point. This line said 39/39, then 47/47, each time going stale
#      inside a week, in the file whose subject is exactly that. `check-tools-selfhost.sh` already checks
#      emitted -> listed, which is weaker in the direction that
#      matters: a code CONSTRUCTED but never reached by a corpus
#      fixture escapes it, and AX4001 sat in the table with no
#      construction site for months.
#
#   2  EVERY COUNT IS RECOMPUTED, IN EVERY PROSE DOCUMENT. A claim
#      whose phrase this gate cannot find is a FAILURE, not a skip - a
#      reworded sentence must not silently stop being checked, which is
#      this repository's standing rule about a sweep that reads fewer
#      files than it should. This half of the gate WAS such a sweep
#      until 2026-08-24: `claim()` opened README.md and nothing else,
#      while sections 3, 4 and 5 below already read the eleven documents
#      `gate_prose_docs` names. The cost was standing in the tree -
#      CONTRIBUTING.md said "449 of the 451 `.ax` files", README.md
#      said 479, the tree had 479, and the gate was green. It reads
#      the same eleven documents now, and reports the file and line.
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
#
#   6  NO TWO CASES IN A TEST DIRECTORY SHARE A NUMERIC PREFIX. Check 4
#      resolves a fixture by bare basename, so a duplicate number
#      resolves happily and is invisible - `tests/stdlib/` carried two
#      `310-` cases for five days with every gate green. The number is
#      the corpus's identity, so two files answering to it means every
#      sentence citing it has two referents.
#
#   7  THE SUPPORTED-TARGET LIST IS ONE FACT. README.md and
#      docs/reference.md carry it, the compiler's `--target` table must
#      accept every name on it, an accepted name off it must be
#      explained, and SECURITY.md's "not a supported target" bullet must
#      cite a document that really states the rule. That bullet cited
#      `CONTRIBUTING.md` for a sentence CONTRIBUTING.md never held, and
#      no check above could see it: they resolve paths, and the path
#      existed.
#
#   8  NO RULE IDENTIFIER IS DEFINED TWICE. `memory-model.md` 0.1 says a
#      rule id is "never renamed, never reused", and on 2026-08-31 three
#      of them were: two `MM-LIFE-2e`, two `MM-LIFE-2f`, two
#      `MM-ALLOC-17`. The document's own section 9 admitted the first
#      pair and declined to repair it; nothing at all knew about the
#      third, which had sat there since 2026-08-25 with a W rule and an
#      H rule answering to one number. A duplicate id is worse than a
#      typo: every citation resolves by number, so half of them point at
#      the wrong rule and no reader can tell which half. This is the
#      cheapest possible check for it and it found a defect the prose
#      had not.
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
  echo "FAIL: only $nc constructed codes found; the floor is 45 (51 today; the grep stopped matching)"
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
# 1b. the RESERVED numbers, against the same constructed set
# ---------------------------------------------------------------
# `docs/error-model.md` keeps a table of codes it PROPOSES and has not
# built. Eight times the compiler has spent a proposed number first, and
# the eighth sat in the table for two days: `AX3041` went to the parser
# as `extern-library-name` while the table still proposed it for
# `recursion-in-scrutinee`, and the paragraph above the table still
# called `AX3041` the next free number.
#
# Nothing caught it, and the document said something WAS catching it -
# "the only thing that keeps it honest is check-doc-drift.sh comparing
# constructed against listed in both directions". That comparison is
# check 1 above, it is a statement about `explain.ax`, and it does not
# read this document at all. A reserved number is invisible to it by
# construction, because a reserved number is one nobody has built.
#
# ONE DIRECTION ONLY, and deliberately. "Proposed and already spent" is
# a contradiction and fails here. "Constructed and not proposed" is the
# normal case for all 58 codes and means nothing. There is no floor on
# the table's size either: it is allowed to empty out as proposals get
# built, and a floor would turn that into a failure.
echo "== registry: no reserved number is already spent =="
model="docs/error-model.md"
[[ -f "$model" ]] || { echo "FAIL: $model is missing"; exit 1; }
# The table rows only - `| \`AXNNNN\` | \`slug\` | ...` - never the
# prose around them, which quotes spent numbers on purpose while
# explaining that they are spent.
proposed="$(grep -ohE '^\| `AX[0-9]{4}` \| `[a-z-]+` \|' "$model" \
              | grep -ohE 'AX[0-9]{4}' | sort -u)"
np="$(printf '%s\n' "$proposed" | grep -c .)"
collide="$(comm -12 <(printf '%s\n' "$proposed") <(printf '%s\n' "$constructed") | tr '\n' ' ')"
if [[ -n "${collide// /}" ]]; then
  echo "FAIL registry: $model proposes numbers the compiler has already built: $collide"
  echo "     renumber the row and the paragraph naming the next free number."
  failed=$((failed+1))
else
  echo "ok   $np reserved number(s) in $model, none of them constructed"
fi

# ---------------------------------------------------------------
# 1d. a document against its OWN defect table
# ---------------------------------------------------------------
# `docs/memory-model.md` §9.0 is the register of defects this
# specification records, and a row leaves it by being struck through and
# marked CLOSED. That table is the source of truth for whether a rule is
# open — and the prose above it is where the reader actually meets the
# rule, so the two can disagree, and did.
#
# `MM-LIFE-2a` closed on 2026-08-25 when `check-arena-reset-rate.sh`
# landed. §9.0 said so the same day. Four hundred lines earlier the
# document still said "no gate anywhere in this repository compares a
# reset carrying the scrub against one without it. §9.0 keeps it as a
# defect on that ground alone" — and stated the superseded number, in
# bold, as the paragraph's heading.
#
# WHY THE NEGATIVE-CLAIMS RULE BELOW DOES NOT CATCH THIS. Its noun list
# deliberately excludes a bare `gate`, measured and written down where
# it is defined: the word means three things in this repository and
# including it matched paragraphs about none of them. Re-measured
# 2026-08-25 — adding it flags 12 paragraphs, 7 with no path, of which
# most are changelog narrative. So this is a DIFFERENT rule with a
# machine-checkable anchor: the rule id. It fires only where a document
# names a rule its own table has closed AND says something about that
# rule being open, which is one paragraph in the tree and was zero after
# the fix.
echo "== documents: nothing described as open is closed in the same file =="
if ! python3 - $(gate_prose_docs) <<'PY'
import re, sys
OPENISH = re.compile(r"still open|no gate|nothing would notice|stays a defect"
                     r"|is unknown|not measured|ungated", re.I)
# A struck-through rule id followed by CLOSED, which is how a row leaves
# the register. Anchored on the table's own syntax rather than on prose.
CLOSED_ROW = re.compile(r"\|\s*~~`([A-Z][A-Z0-9-]*-[0-9]+[a-z]?)`~~\s*\|\s*\*\*CLOSED")
bad = 0
checked = 0
for doc in sys.argv[1:]:
    text = open(doc, encoding="utf-8").read()
    closed = set(CLOSED_ROW.findall(text))
    if not closed:
        continue
    checked += len(closed)
    for para in re.split(r"\n\s*\n", text):
        # The register itself is exempt: a CLOSED row says what the
        # defect WAS, so it quotes the open language on purpose.
        if not para.strip() or para.lstrip().startswith("|"):
            continue
        m = OPENISH.search(para)
        if not m:
            continue
        for rule in sorted(closed):
            if rule in para:
                line = text.count("\n", 0, text.index(para)) + 1
                print(f"FAIL closed-rules: {doc}:{line} describes `{rule}` as open —")
                print(f"  it says {m.group(0)!r} — while this document's own defect")
                print(f"  register marks it CLOSED. The register is the source of truth;")
                print(f"  correct the prose, or reopen the row and say why.")
                print(f"  | {' '.join(para.split())[:140]}")
                bad += 1
if bad:
    sys.exit(1)
print(f"ok   {checked} closed defect rule(s), none described as open elsewhere")
PY
then failed=$((failed+1)); fi

# ---------------------------------------------------------------
# 1c. the WARNING allowlist, against the document that restates it
# ---------------------------------------------------------------
# `tests/diagnostics/severity.policy` decides which codes may render as
# warnings, and `docs/agent-harness.md` names them in prose - which is a
# restatement, and restatements go stale. This one did: `AX3040` was
# promoted to an error on 2026-08-25 and left the policy file the same
# day, and the document went on saying "the only five codes permitted to
# render as warnings" and listing it among them.
#
# Nothing caught it. The `claim()` sweep below recomputes NUMBERS a
# document states, and this sentence spells its number as a word; even
# had it been a numeral, a count is the weaker half of the claim. The
# SET is what matters, so the set is what is compared, in both
# directions.
echo "== registry: the warning allowlist, against the document that quotes it =="
if ! python3 - "tests/diagnostics/severity.policy" "docs/agent-harness.md" <<'PY'
import re, sys
policy, doc = sys.argv[1], sys.argv[2]
allowed = {l.strip() for l in open(policy, encoding="utf-8")
           if l.strip() and not l.lstrip().startswith("#")}
if not allowed:
    print(f"FAIL warnings: {policy} lists no codes at all - a policy that permits "
          f"nothing would make every comparison below vacuous")
    sys.exit(1)
text = open(doc, encoding="utf-8").read()
# ONE PARAGRAPH, not the whole document: the document also discusses
# codes that used to be on this list and must be free to, which a
# document-wide scan would read as a claim.
paras = [p for p in text.split("\n\n") if "permitted to render as warnings" in p]
if len(paras) != 1:
    print(f"FAIL warnings: {len(paras)} paragraphs of {doc} claim to quote the "
          f"allowlist; this gate reads exactly one - if the sentence moved or was "
          f"reworded, reword the gate with it rather than narrowing this")
    sys.exit(1)
quoted = set(re.findall(r"AX\d{4}", paras[0]))
if quoted != allowed:
    print(f"FAIL warnings: {doc} quotes {sorted(quoted) or 'nothing'}; "
          f"{policy} permits {sorted(allowed)}")
    sys.exit(1)
print(f"ok   {doc} quotes exactly the {len(allowed)} codes {policy} permits")
PY
then failed=$((failed+1)); fi

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
    """A numeric claim in the prose, recomputed - in every document
    `gate_prose_docs` names, which is the list every other prose sweep
    in this repository reads and was already this file's list for the
    fixture-path checks below.

    It read README.md alone until 2026-08-24, and the drift standing in
    the tree the day it was widened is exactly what that cost:
    CONTRIBUTING.md said "449 of the 451 `.ax` files" while README.md,
    checked by this helper, said 479 and passed. One claim, two
    documents, 28 files apart, in the gate whose subject is that class
    of sentence - and it was green. A count restated in a second
    document is the same claim, so it is checked in every document it
    appears in, and each report names the file and the line.

    A pattern that matches in NO document is still a failure, for the
    reason it always was: a reworded sentence must not silently stop
    being checked, which reads exactly like success."""
    global bad
    seen = 0
    for doc in PROSE_DOCS:
        text = open(doc, encoding="utf-8").read()
        for m in re.finditer(pattern, text):
            seen += 1
            stated = int(m.group(1))
            line = text.count("\n", 0, m.start()) + 1
            if stated != actual:
                print(f"FAIL counts: {doc}:{line} says {stated} {label}, "
                      f"measured {actual}")
                bad += 1
            else:
                print(f"ok   {label}: {actual} ({doc}:{line})")
    if not seen:
        print(f"FAIL counts: the claim about {label} is not where this gate looks "
              f"(pattern {pattern!r} matches none of the {len(PROSE_DOCS)} prose "
              f"documents) - reword the gate with the sentence")
        bad += 1

ax_files = len([p for p in glob.glob("**/*.ax", recursive=True)])
corpus_cases = sum(
    sum(1 for line in open(p, encoding="utf-8") if line.startswith("==="))
    for p in glob.glob("tree-sitter-axiom/test/corpus/*.txt")) // 2

print("== counts: every number the prose documents state is recomputed ==")
# The patterns are the SENTENCE's numeral and its unit, not one
# document's phrasing around it. README.md writes "gated against all 479
# `.ax` files in the repo" and CONTRIBUTING.md writes "the 479 `.ax`
# files in the repository"; anchoring on the README's lead-in, as this
# did, would have kept the second sentence outside the sweep even after
# the sweep learned to open the second file.
#
# Which cuts the other way too, deliberately: a sentence counting `.ax`
# files in ONE DIRECTORY now fails here against the repository total.
# That is the failure this gate prefers - loud and wrong over quiet and
# absent - and the fix for it is to scope THAT claim, not to narrow the
# pattern back until it matches one document's wording again.
claim("`.ax` files in the repo", r"(\d+) `\.ax` files", ax_files)
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
# The working-notes document was NOT in this list once, and the omission
# bit immediately: a commit landed three sections naming three fixtures
# and only one of them existed, and this gate passed. It was the
# document that named the most fixtures, because every section ended by
# saying what pinned it - which is also why the floor below moved when
# it was retired.
historical = set()
for doc in PROSE_DOCS:
    # The extension alternation needs the boundary: without it
    # `tests/fmt/parity/170-empty-tuple.axp` matched as `...ax` and was
    # reported missing, which is a gate finding its own bug and calling
    # it drift. Caught on this gate's first run.
    found = set(re.findall(r"tests/[\w./-]+\.(?:axbad|axp|ax|py|sh|out|golden)(?![\w])",
                           open(doc, encoding="utf-8").read()))
    # CHANGELOG.md is the one document that describes the PAST, and it
    # is append-only: an entry for 0.3.0 saying a rule was pinned by a
    # fixture was TRUE of 0.3.0, and stays true after the fixture is
    # deleted. Demanding those paths exist in the working tree makes
    # every removal a choice between a red gate and falsified history -
    # which is what removing traits in 0.6.0 ran into, with four
    # entries naming four fixtures that shipped and were later deleted
    # with the construct they tested.
    #
    # So they are resolved against git instead of the filesystem. A
    # path git has never heard of is still a failure, which is the case
    # that actually matters: a typo, or a fixture renamed without its
    # citation following. Nothing is exempted - the question asked of
    # this one file is just "did this ever exist" rather than "does it
    # exist now", and a reader can `git log` their way to it.
    if os.path.basename(doc) == "CHANGELOG.md":
        historical |= found
    else:
        named |= found
# The floor is a population count, so it moves when the corpus moves -
# and it has to be re-derived deliberately, because the failure it
# guards against (a doc quietly stopping citing its fixtures) and the
# reason it legitimately drops (a doc being retired) look identical
# from here. It was 185 while the working-notes document was in
# PROSE_DOCS; that document was deleted on 2026-08-23 and the eight
# that remain name 153, all of which resolve. Lowering it to match is
# correct ONLY because the drop was accounted for. A drop that is not
# accounted for is the drift this number exists to catch.
if len(named) < 153:
    print(f"FAIL paths: only {len(named)} tests/ paths named across the docs; floor is 153")
    bad += 1
missing = sorted(p for p in named if not os.path.exists(p))
if missing:
    for p in missing:
        print(f"FAIL paths: the docs name {p}, which does not exist")
    bad += len(missing)
else:
    print(f"ok   all {len(named)} tests/ paths named in the docs exist")

# The historical ones. `git log -- <path>` is empty for a path no
# commit ever touched, and non-empty for one that was added and later
# deleted, which is exactly the distinction wanted.
hist_gone = sorted(p for p in historical if not os.path.exists(p))
# A SHALLOW CLONE CANNOT ANSWER THIS QUESTION, and saying so is the
# only honest thing to do with it. CI checks out with the default depth
# for every job but the four that ask for `fetch-depth: 0`, and a
# one-commit clone has no history in which a deleted fixture was ever
# added - so `git log -- <path>` is empty for EVERY historical citation
# and this check reported all four of them as fabricated. Measured
# 2026-08-31 by cloning this repository with `--depth 1` and running
# the gate: four FAILs, none of them real.
#
# The fix is not `fetch-depth: 0` on every job - that is a full-history
# clone on every push of a five-target matrix, to check a changelog.
# It is for the check to know what it cannot see. It still runs
# wherever history exists: locally, and on the four jobs that fetch it.
shallow = subprocess.run(["git", "rev-parse", "--is-shallow-repository"],
                         capture_output=True, text=True)
is_shallow = shallow.stdout.strip() == "true"
if is_shallow and hist_gone:
    print(f"ok   {len(historical)} tests/ paths named in CHANGELOG.md; "
          f"{len(hist_gone)} NOT CHECKED HERE - resolving a deleted fixture "
          f"needs history this shallow clone does not have")
else:
    hist_bad = []
    for p in hist_gone:
        r = subprocess.run(["git", "log", "--oneline", "-1", "--", p],
                           capture_output=True, text=True)
        if r.returncode != 0 or not r.stdout.strip():
            hist_bad.append(p)
    if hist_bad:
        for p in hist_bad:
            print(f"FAIL paths: CHANGELOG.md names {p}, which no commit ever added")
        bad += len(hist_bad)
    else:
        print(f"ok   all {len(historical)} tests/ paths named in CHANGELOG.md resolve "
              f"({len(hist_gone)} only in history)")

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
# A population count, and it moves for the same reason and under the
# same rule as the one above: 82 while the working-notes document was
# in the tree, 79 after it was retired on 2026-08-23. Three bare names
# went with it and all 79 that remain resolve.
if len(bare_named) < 79:
    print(f"FAIL paths: only {len(bare_named)} bare fixture names found; floor is 79")
    bad += 1
bare_missing = sorted((p, fs) for p, fs in bare_named.items() if p not in tests_index)
if bare_missing:
    for p, fs in bare_missing:
        for f in sorted(set(fs)):
            print(f"FAIL paths: {f} names {p}, which is not a file under tests/")
    bad += len(bare_missing)
else:
    print(f"ok   all {len(bare_named)} bare fixture names resolve under tests/")

# The same class one directory up, and the one that had no check at all
# until 2026-08-23: a NORMATIVE DOCUMENT that is named but not there.
# Every check above sweeps for `tests/`, so a document could be deleted
# and leave 82 references behind it across 30 files - prose links in
# README.md and CONTRIBUTING.md, provenance citations in the compiler's
# own comments, and two strings the compiler PRINTS - and the only
# thing that failed was three gates dying on a traceback, which reads
# as a broken gate rather than as drift. It was drift. This is the
# check that says so.
#
# Both directions, because a hand-written sweep list drifts both ways:
#   - a document named anywhere in the tree must exist, and
#   - a document that exists under `docs/` must be in `gate_prose_docs`,
#     or it is swept by no gate and its code blocks are never compiled.
# The second half is the older bug: it is the sentence `gate.sh` already
# carried about two documents that were in the tree and in nobody's list.
print("== every docs/ document named in the tree exists, and is swept ==")
doc_named = {}
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs
               if d not in (".git", "target", "node_modules", ".axiom-bin")]
    for fn in files:
        if not fn.endswith((".ax", ".sh", ".py", ".md", ".yml")):
            continue
        path = os.path.join(root, fn).lstrip("./")
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        # A retired document may still be NAMED - saying what was
        # deleted and why is what a history section is for - provided
        # the same file says how to read it. `docs/ffi.md` was already
        # doing this before this check existed: it names a design note
        # it deleted, in prose, and then gives the `git show` that
        # retrieves it. That reference is not dangling; a reader can
        # follow it. So the rule is not "never name a deleted file",
        # which would delete the history along with the document - it
        # is that a file naming one must also carry its retrieval.
        retrievable = set(re.findall(
            r"git show [0-9a-f]{7,40}\^?:(docs/[\w./-]+\.md)", text))
        for d in re.findall(r"docs/[\w./-]+\.md(?![\w])", text):
            if d in retrievable:
                continue
            doc_named.setdefault(d, []).append(path)
        # A MARKDOWN LINK TARGET, resolved against the file that writes
        # it. Inside `docs/` a sibling is spelled `memory-model.md`, not
        # `docs/memory-model.md` - the relative form is the normal one
        # there - so the absolute sweep above is blind to exactly the
        # spelling those documents use on each other. Found the way
        # these are always found: this gate passed with two dangling
        # links to a retired document standing in `docs/reference.md`,
        # because neither carried the prefix the pattern needed. This
        # paragraph does not spell one out, for the same reason the
        # sibling checks above do not name the fixtures they were
        # written for: the example would resolve against `scripts/` and
        # be reported as drift by the check it explains - which this
        # one did, on its first run. Link targets are matched instead of bare
        # filenames so that PROSE naming a document - and this
        # paragraph does - is not read as a reference to it.
        #
        # A FILE MAY DECLARE WHERE ITS LINKS RESOLVE FROM, and exactly
        # one does: `examples/axdoc/axdoc.ax` writes the markdown of
        # `docs/stdlib-api.md`, so the links in its string literals are
        # relative to `docs/` and resolving them against
        # `examples/axdoc/` reports two dangling links that are not
        # dangling. The alternative was to stop emitting links, or to
        # build them from two string pieces so this pattern would not
        # see them - and a check evaded by splitting a literal in half
        # is worse than no check. The declaration is greppable, names a
        # directory that must exist, and applies only to the file that
        # carries it.
        base = os.path.dirname(path)
        declared = re.search(r"doc-links-resolve-from: *([\w./-]+)", text)
        if declared:
            base = declared.group(1)
            if not os.path.isdir(base):
                print(f"FAIL docs: {path} resolves its links from {base}, "
                      f"which is not a directory")
                bad += 1
        for tgt in re.findall(r"\]\(([\w./-]+\.md)(?:#[\w-]*)?\)", text):
            if tgt.startswith("docs/") or tgt in retrievable:
                continue
            resolved = os.path.normpath(os.path.join(base, tgt))
            if not os.path.exists(resolved):
                doc_named.setdefault(resolved, []).append(path)
doc_missing = sorted((d, fs) for d, fs in doc_named.items() if not os.path.exists(d))
if doc_missing:
    for d, fs in doc_missing:
        for f in sorted(set(fs)):
            print(f"FAIL docs: {f} names {d}, which does not exist")
    bad += len(doc_missing)
else:
    print(f"ok   all {len(doc_named)} docs/ documents named in the tree exist")

# `PROSE_DOCS` arrives from `gate_prose_docs`; compare it against the
# tree rather than trusting it. A document under `docs/` that is not in
# the list is compiled by nothing and cited-checked by nothing.
on_disk = {os.path.join("docs", f)
           for f in os.listdir("docs") if f.endswith(".md")}
listed = {d for d in PROSE_DOCS if d.startswith("docs/")}
unswept = sorted(on_disk - listed)
phantom = sorted(listed - on_disk)
for d in unswept:
    print(f"FAIL docs: {d} exists but is in no gate's sweep list")
for d in phantom:
    print(f"FAIL docs: the sweep list names {d}, which does not exist")
bad += len(unswept) + len(phantom)
if not unswept and not phantom:
    print(f"ok   the sweep list and docs/ agree, {len(listed)} documents")

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

# ---------------------------------------------------------------
# 5b. A NEGATIVE CLAIM ABOUT THE CORPUS MUST NAME ITS PROBE.
#
# `docs/memory-model.md` section 9.1 states this as a documentation
# rule. This is the gate that makes it one, and the reason it is worth
# having is that every check above proves reference INTEGRITY - the
# fixtures a document NAMES all exist - which is the exact dual of what
# went wrong. `memory-model.md` said status 70 was "the one no fixture
# can reach without exhausting memory" while
# `tests/stdlib/314-out-of-memory.ax` reached it deterministically. A
# sentence asserting a NON-existence names no path, so there is nothing
# for check 4 to resolve, and it sailed through green.
#
# It was demonstrated rather than argued, on 2026-08-24: a document
# edited to say the opposite of what three of its own fixtures prove
# passed both this gate and `check-tree-sitter.sh`, exit 0 from each.
#
# THE ENFORCEMENT IS THE CHEAP PART, and it is why the rule is spelled
# this way: a negative claim that NAMES a path stops being a negative
# claim as far as this gate is concerned - it becomes an ordinary path
# reference, and check 4 above already resolves it. The rule does not
# need a new verifier, only a new refusal.
#
# THE POPULATION IS WHY IT LANDS NOW. The tree holds four sentences of
# this shape and three are narrative about this very defect. A rule
# demanding annotation on 145 sentences would be argued with and then
# switched off; at four it costs nothing to adopt, and it is the last
# moment that is true. The ceiling below is what keeps that from
# rotting: exemptions cannot grow silently.
# ---------------------------------------------------------------
NEG_MARK = re.compile(r"<!--\s*doc-gate:negative\s+(\S+)\s*-->")
NEG_EXEMPT = re.compile(r"<!--\s*doc-gate:negative-exempt\s+(.+?)\s*-->")

# A negative quantifier and a corpus noun in one sentence. Deliberately
# narrow: it is the class that produced the defect, and it is the class
# a gate can do something about, because the remedy is a path.
#
# TUNED AGAINST THE TREE RATHER THAN GUESSED. A bare `gate` is not in
# the noun list: this repository calls the driver's error path a gate
# and a policy region a gate, and including the word matched eleven
# paragraphs of which six were about neither fixtures nor tests. The
# window is 60 characters rather than 160 for the same reason - at 160
# a `no` at the head of a sentence reached a `corpus` at its tail with
# a whole clause in between, which is a coincidence and not a claim.
# Five paragraphs match at these settings and all five were read.
NEG_CORPUS = re.compile(
    r"\b(?:no|No|nothing|Nothing|never|Never|cannot|only|Only)\b"
    r"[^.\n]{0,60}?"
    r"\b(?:fixture|fixtures|probe|probes|test case|test cases|corpus)\b",
)
# A path is the remedy the rule names, so any of these satisfies it.
HAS_PATH = re.compile(r"\b(?:tests|scripts)/[A-Za-z0-9_./-]+")

EXEMPT_CEILING = 5
exemptions = 0
neg_checked = 0
neg_bad = 0

for doc in PROSE_DOCS:
    text = open(doc, encoding="utf-8").read()
    lines = text.split("\n")
    # Paragraph-wise, because a claim wraps across lines in these files
    # and a line-wise sweep would cut sentences in half.
    start = 0
    for para in re.split(r"\n\s*\n", text):
        nl = text.count("\n", 0, start)
        start += len(para) + 2
        if not para.strip():
            continue
        if NEG_EXEMPT.search(para):
            reason = NEG_EXEMPT.search(para).group(1).strip()
            if len(reason) < 12:
                print(f"FAIL negative: {doc} carries a doc-gate:negative-exempt with no real reason")
                print(f"  an exemption is a claim that the sentence is narrative rather than normative,")
                print(f"  and it has to say why in words a reader can disagree with")
                bad += 1
            exemptions += 1
            continue
        if not NEG_CORPUS.search(para):
            continue
        neg_checked += 1
        if HAS_PATH.search(para) or NEG_MARK.search(para):
            m = NEG_MARK.search(para)
            if m:
                named = m.group(1)
                if not os.path.exists(named):
                    print(f"FAIL negative: {doc} marks a negative claim with the probe {named},")
                    print(f"  which does not exist - the marker is the whole point and it names nothing")
                    bad += 1
            continue
        first = " ".join(para.split())[:150]
        line_no = nl + 1
        print(f"FAIL negative: {doc}:{line_no} asserts a negative about the corpus and names no probe")
        print(f"  | {first}")
        print(f"  A sentence saying a fixture does NOT exist is invisible to every other check in")
        print(f"  this gate, because they resolve the paths a document names and this names none.")
        print(f"  Name the tests/ path that would exist if the negative became false, or mark it")
        print(f"  <!-- doc-gate:negative-exempt <why this is narrative, not a standing claim> -->")
        neg_bad += 1
        bad += 1

if exemptions > EXEMPT_CEILING:
    print(f"FAIL negative: {exemptions} exemptions, ceiling {EXEMPT_CEILING}")
    print(f"  An exemption silences the rule for one paragraph. Five is the number the tree had")
    print(f"  when the rule landed, and each one was read and its reason written by hand.")
    print(f"  Growth means the rule is being routed around - raise the ceiling deliberately,")
    print(f"  in a commit that says which claim needed it and why it could not name a path.")
    bad += 1
elif neg_bad == 0:
    print(f"ok   negative claims about the corpus: {neg_checked} checked, {exemptions}/{EXEMPT_CEILING} exempt")

sys.exit(1 if bad else 0)
PY
[[ $? -eq 0 ]] || failed=$((failed+1))

# ---------------------------------------------------------------
# 6. ONE NUMBER, ONE CASE, within a test directory.
#
# Check 4 resolves the fixture a comment names by BARE BASENAME, and
# that is precisely why this went unseen: on 2026-08-24 `tests/stdlib/`
# held `310-effect-unhandled.ax` alongside a second case numbered 310 -
# the signal-in-poll fixture, added five days later - and every name in
# every document still resolved. No gate was red, and check 4 could not
# have gone red, because both basenames were real files and it asks
# nothing else. But the numeric prefix is this corpus's identity -
# drivers, goldens and prose all reach for a case as "310" and expect
# one file back - so a repeated prefix makes every sentence
# about that number ambiguous and leaves the reader to guess which of
# the two it meant. The newer of that pair is `315-signal-in-poll.ax`
# as of this commit; the check below is what would have caught it on
# the day it landed.
#
# THE TEN PAIRS BELOW PREDATE THE RULE, across four directories, and
# their numbers are already load-bearing in goldens and documents that
# this change does not own - renumbering them is a separate change with
# its own blast radius. They are grandfathered by exact MEMBERSHIP
# rather than by number, which is what stops the list from being a hole
# in the check: a THIRD file landing on an allowlisted number changes
# that entry's membership and still fails. An entry whose collision has
# been resolved fails as stale, so the list can only shrink, and it
# cannot quietly stop applying - a frozen allowlist nobody is forced to
# revisit is how a gate keeps passing after its premise has moved.
#
# The entries below are also checked by check 4, for free and from the
# other side: they are bare `NNN-name.ax` spellings in a swept source,
# so a grandfathered file that is renamed or deleted is reported there
# as a name that resolves to nothing. Observed while probing this
# section - two invented names in this list failed check 4 immediately.
# ---------------------------------------------------------------
echo "== corpus: no two cases in a test directory share a numeric prefix =="
dupwork="$work/prefix"
mkdir -p "$dupwork"
# Every "ok" in this gate has to mean the whole section passed. Comparing
# only the KEYS here printed "no unaccounted collisions" underneath a
# membership failure it had just reported, which is the shape of message
# a reader trusts and skips.
dup_before=$failed

# The prefix is the literal run of leading digits. Every test directory
# that numbers its cases pads to three today - diagnostics, frontend,
# lsp, selfhost and stdlib are all width 3 - so literal and numeric
# agree; a `10-` landing beside `010-` is padding drift, which this
# does not claim to catch.
for d in "$repo_root"/tests/*/; do
  [[ -d "$d" ]] || continue
  rel="tests/$(basename "$d")"
  for f in "$d"*.ax; do
    [[ -e "$f" ]] || continue
    b="$(basename "$f")"
    [[ "$b" =~ ^([0-9]+)- ]] || continue
    printf '%s:%s %s\n' "$rel" "${BASH_REMATCH[1]}" "$b"
  done
done | LC_ALL=C sort > "$dupwork/all"

# `dir:NNN member member ...`, one line per number that repeats.
awk '{
  if ($1 == prev) { members = members " " $2; n++ }
  else { if (n > 1) print prev " " members; prev = $1; members = $2; n = 1 }
} END { if (n > 1) print prev " " members }' "$dupwork/all" \
  | LC_ALL=C sort > "$dupwork/observed"

LC_ALL=C sort > "$dupwork/grandfathered" <<'DUPS'
tests/diagnostics:340 340-axtag-pure-io.ax 340-effect-op-value.ax
tests/diagnostics:370 370-mixed-warning-error.ax 370-private-name.ax
tests/diagnostics:380 380-gutter-three-digits.ax 380-private-name-filtered.ax
tests/frontend:070 070-derive-macro.ax 070-import.ax
tests/selfhost:380 380-literal-patterns.ax 380-syntax-scalar-queries.ax
tests/selfhost:390 390-multi-rule-macro.ax 390-nested-patterns.ax
tests/selfhost:993 993-filesystem-verbs.ax 993-let-body-tail-call.ax
tests/selfhost:994 994-deep-release-first-field.ax 994-directory-listing.ax
tests/stdlib:210 210-flags-across-syscall.ax 210-struct-variants.ax
tests/stdlib:300 300-effect-handlers.ax 300-process.ax
DUPS

awk '{print $1}' "$dupwork/observed" | LC_ALL=C sort > "$dupwork/keys.observed"
awk '{print $1}' "$dupwork/grandfathered" | LC_ALL=C sort > "$dupwork/keys.grandfathered"

# Name every colliding file by the path a reader can open.
dup_report() {
  local key="$1" table="$2" line dir b
  dir="${key%%:*}"
  line="$(grep -m1 "^$key " "$table")"
  for b in ${line#* }; do echo "     $dir/$b"; done
}

while read -r key; do
  [[ -n "$key" ]] || continue
  echo "FAIL prefix: ${key%%:*} has more than one case numbered ${key##*:}:"
  dup_report "$key" "$dupwork/observed"
  echo "     renumber the newer one to a free number in that directory"
  failed=$((failed+1))
done < <(LC_ALL=C comm -23 "$dupwork/keys.observed" "$dupwork/keys.grandfathered")

while read -r key; do
  [[ -n "$key" ]] || continue
  echo "FAIL prefix: the grandfathered collision $key is stale - ${key%%:*} no longer"
  echo "     has two cases numbered ${key##*:}. Delete its line from this gate;"
  echo "     the allowlist is only allowed to shrink."
  failed=$((failed+1))
done < <(LC_ALL=C comm -13 "$dupwork/keys.observed" "$dupwork/keys.grandfathered")

while read -r key; do
  [[ -n "$key" ]] || continue
  obs="$(grep -m1 "^$key " "$dupwork/observed")"
  old="$(grep -m1 "^$key " "$dupwork/grandfathered")"
  if [[ "$obs" != "$old" ]]; then
    echo "FAIL prefix: the collision at $key is no longer the pair that was grandfathered:"
    dup_report "$key" "$dupwork/observed"
    echo "     grandfathered as: ${old#* }"
    failed=$((failed+1))
  fi
done < <(LC_ALL=C comm -12 "$dupwork/keys.observed" "$dupwork/keys.grandfathered")

numbered="$(wc -l <"$dupwork/all" | tr -d ' ')"
grand="$(wc -l <"$dupwork/grandfathered" | tr -d ' ')"
# A glob that stops matching reports a clean tree, which reads exactly
# like success - the same trap rule 2 states for the prose claims.
if (( numbered < 300 )); then
  echo "FAIL prefix: only $numbered numbered .ax cases found; the floor is 300 (354 today)"
  failed=$((failed+1))
fi
if (( failed == dup_before )); then
  echo "ok   $numbered numbered cases, no unaccounted collisions ($grand grandfathered)"
fi

# --------------------------------------------------------------------
echo "== types: README's LLVM column, against what the emitter actually writes =="
# --------------------------------------------------------------------
# The column was WRONG FOR SEVEN OF NINE ROWS until 2026-08-25, and had
# been for as long as the self-hosted compiler existed: it said `f64`,
# `i1`, `i8`, `ptr` and `void`, which is what the RUST compiler lowered
# to. This one is uniformly word-wide - a type is a checking-time
# distinction that carries no representation - so `(-> Bool Bool)` emits
# `define i64 @f(i64)` and so does every other row.
#
# Nothing caught it because nothing read the column. A table of facts
# about the emitter is checkable against the emitter, so this compiles
# one probe per row and reads the `define` line back.
#
# THE TYPE GOES IN PARAMETER POSITION on purpose. In return position a
# probe needs a VALUE of the type, which means a `cast` for `Unit` and
# `Void` and is not expressible at all for `()` - so the shape of the
# probe would vary per row and the rows would stop being comparable.
# A parameter needs no value.
#
# AND `main` HOLDS A BARE REFERENCE TO `g`, which is not decoration.
# Until 2026-08-31 the probe never mentioned `g` at all, and once the
# emitter stopped writing functions a program cannot reach
# (`pruneDeadDefs`) there was no `define @g` left to read: all nine
# rows failed at "the probe stopped measuring", which is that check
# doing its job. Calling `g` would need a value of the row's type and
# would undo the paragraph above, so `main` binds it instead - a bare
# reference to a one-argument function makes `g` reachable through the
# thunk the emitter synthesises, and leaves the `define` line this
# reads byte-identical. Verified across all nine rows.
types_before=$failed
tw="$work/types"; mkdir -p "$tw"
row_n=0
while IFS='|' read -r ty want; do
  [[ -z "$ty" ]] && continue
  row_n=$((row_n + 1))
  printf '(:: g (-> %s Int))\n\n(fn (g x) 0)\n\n(:: main Int)\n\n(fn (main) (let ((h g)) 0))\n' "$ty" > "$tw/t.ax"
  if ! ( cd "$tw" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" build \
           --input t.ax --output t.bin --emit-llvm ) >/dev/null 2>&1; then
    echo "FAIL types: the probe for \`$ty\` does not compile - README names a type the compiler will not take"
    failed=$((failed+1)); continue
  fi
  got="$(grep -oE '^define [a-z0-9]+ @g\([a-z0-9]+' "$tw/t.bin.ll" | head -1 | sed -E 's/.*@g\(//')"
  if [[ -z "$got" ]]; then
    echo "FAIL types: no \`define @g\` in the emitted IR for \`$ty\` - the probe stopped measuring"
    failed=$((failed+1)); continue
  fi
  if [[ "$got" != "$want" ]]; then
    echo "FAIL types: README says \`$ty\` lowers to \`$want\`; the emitter writes \`$got\`"
    failed=$((failed+1))
  fi
done <<< "$(awk '
  /^\| Type \| Description \| LLVM type \|/ { intable = 1; next }
  intable && /^\|---/ { next }
  intable && !/^\|/ { intable = 0 }
  intable {
    # first cell is the type, LAST cell is the LLVM type; a Description
    # containing a `|` would break a naive split, so take the ends.
    n = split($0, c, "|")
    ty = c[2]; lv = c[n-1]
    gsub(/^[ \t]*`?|`?[ \t]*$/, "", ty)
    gsub(/^[ \t]*`?|`?[ \t]*$/, "", lv)
    if (ty != "" && lv != "") print ty "|" lv
  }
' README.md)"
if (( row_n < 8 )); then
  echo "FAIL types: read $row_n row(s) out of README's table; the parse broke and this section is checking almost nothing"
  failed=$((failed+1))
elif (( failed == types_before )); then
  echo "ok   all $row_n documented types lower to what README's LLVM column says"
fi

# --------------------------------------------------------------------
echo "== targets: one supported list, the compiler's table, and SECURITY.md's exclusion =="
# --------------------------------------------------------------------
# The supported-target list is one fact with copies: README.md's
# `Supported:` line under `### Targets`, docs/reference.md's `Supported
# targets:` line, the names `--help` accepts for `--target`, and, from
# the other side, SECURITY.md's out-of-scope bullet saying an OS is NOT
# on it. SECURITY.md said "`CONTRIBUTING.md` says so" about Windows for
# as long as the bullet existed, and CONTRIBUTING.md said nothing of the
# kind - a cross-file claim that no check above could see, because the
# checks above resolve PATHS and this names a document that exists.
#
# So this reads the claim the way a reader would follow it:
#
#   1. the two prose copies of the list are the same set;
#   2. every listed name is one the compiler accepts (`--help` names it
#      and `emit-llvm --target=<name>` succeeds), so the list cannot
#      promise a target the binary refuses;
#   3. a name the compiler accepts and the list does NOT carry must be
#      explained in the README's Targets section by its OS - a target
#      that is emitted for but not supported is exactly the state the
#      Windows and FreeBSD work passes through, and the README's rule
#      says what it is; silence would read as "supported";
#   4. SECURITY.md's "**<OS>.** Not a supported target" bullet must name
#      the document that states the rule, that document must contain
#      the rule's sentence, and no `<os>-*` name may be on the list.
#
# The negative probe is the one the bullet failed for real: point the
# bullet at a document without the sentence and this goes red.
python3 - "$axc" <<'PY'
import re, subprocess, sys, tempfile, os
axc = sys.argv[1]
bad = 0
RULE = "executes what the compiler emits there"

def names_in(text, lead):
    m = re.search(lead + r"((?:`[a-z0-9_]+-[a-z0-9_]+`(?:,\s*)?)+)\.", text)
    if not m:
        return None
    return set(re.findall(r"`([a-z0-9_-]+)`", m.group(1)))

readme = open("README.md", encoding="utf-8").read()
sec = re.search(r"^### Targets\n(.*?)(?=^### )", readme, re.S | re.M)
if not sec:
    print("FAIL targets: README.md has no `### Targets` section"); sys.exit(1)
targets_section = sec.group(1)
# Prose wraps at 72 columns, so a sentence is compared with its
# whitespace folded; a rule split across a line break is still the rule.
def flat(t): return " ".join(t.split())
readme_list = names_in(targets_section, r"Supported: ")
ref_list = names_in(open("docs/reference.md", encoding="utf-8").read(), r"Supported targets: ")
if readme_list is None or ref_list is None:
    print("FAIL targets: the `Supported:` line is not where this gate looks (README.md's "
          "Targets section, docs/reference.md) - reword the gate with the sentence")
    sys.exit(1)
if len(readme_list) < 3:
    print(f"FAIL targets: README lists only {len(readme_list)} supported target(s); the floor is 3")
    bad += 1
if readme_list != ref_list:
    print(f"FAIL targets: README.md lists {sorted(readme_list)}, docs/reference.md lists "
          f"{sorted(ref_list)} - one fact, two copies, and they disagree")
    bad += 1
if RULE not in flat(targets_section):
    print(f"FAIL targets: README's Targets section no longer states the rule ({RULE!r}); "
          f"every other document points at it")
    bad += 1

# 2. the compiler's own table, both by `--help` and by doing it.
help_text = subprocess.run([axc, "--help"], capture_output=True, text=True).stdout
m = re.search(r"--target <NAME>\s+([a-z0-9_, -]+)\n", help_text)
if not m:
    print("FAIL targets: `axiom --help` has no `--target <NAME>` line to read the accepted names from")
    sys.exit(1)
accepted = {n.strip() for n in m.group(1).split(",") if n.strip()}
work = tempfile.mkdtemp()
probe = os.path.join(work, "t.ax")
open(probe, "w").write("(:: main Int)\n\n(fn (main) 0)\n")
for name in sorted(readme_list):
    if name not in accepted:
        print(f"FAIL targets: README lists `{name}` as supported, and `--help` does not accept it")
        bad += 1
    r = subprocess.run([axc, f"--target={name}", "emit-llvm", probe, "-o", os.path.join(work, "t.ll")],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAIL targets: README lists `{name}` as supported, and the compiler refuses it: "
              f"{(r.stderr or r.stdout).strip()[:120]}")
        bad += 1

# 3. accepted but not listed: the README must say what it is.
for name in sorted(accepted - readme_list):
    osname = name.split("-", 1)[0]
    if not re.search(r"\b" + osname + r"\b", targets_section, re.I):
        print(f"FAIL targets: the compiler accepts `--target={name}` and README's Targets section "
              f"neither lists it as supported nor mentions {osname} - an unexplained target reads as a supported one")
        bad += 1

# 4. SECURITY.md's exclusion, followed the way a reader follows it.
security = open("SECURITY.md", encoding="utf-8").read()
# PER TARGET, NOT PER OS, since 2026-08-30. The bullet used to name an
# operating system - "**Windows.** Not a supported target" - and the
# check asked whether README's list carried any target starting with
# that OS. `freebsd-x86_64` and `windows-x86_64` joined the list that
# day, which left every OS in it (darwin, freebsd, linux, windows) with
# at least one supported target: no OS-keyed bullet could be true any
# more, and this gate REQUIRES at least one bullet to exist. The
# premise had become unsatisfiable, so the key is now the target name
# itself, which is what the rule was always about.
bullets = re.findall(r"- \*\*([a-z0-9]+-[a-z0-9_]+)\.\*\* Not a supported target\.?(.*?)(?=\n- |\n\n)", security, re.S)
if not bullets:
    print("FAIL targets: SECURITY.md has no `**<OS>.** Not a supported target` bullet - the sentence "
          "this section was written for has moved; reword the gate with it")
    bad += 1
for osname, rest in bullets:
    cited = re.findall(r"`([A-Za-z0-9_./-]+\.md)`", rest)
    if not cited:
        print(f"FAIL targets: SECURITY.md's {osname} bullet names no document for the rule it leans on")
        bad += 1
        continue
    doc = cited[0]
    if not os.path.exists(doc):
        print(f"FAIL targets: SECURITY.md's {osname} bullet cites {doc}, which does not exist")
        bad += 1
        continue
    if RULE not in flat(open(doc, encoding="utf-8").read()):
        print(f"FAIL targets: SECURITY.md's {osname} bullet says {doc} states the rule, and {doc} "
              f"does not contain {RULE!r} - the cross-reference is dangling, which is the defect "
              f"this section exists for")
        bad += 1
    if osname in readme_list:
        print(f"FAIL targets: SECURITY.md says {osname} is not a supported target, and README's "
              f"Supported list carries it")
        bad += 1
if not bad:
    print(f"ok   {len(readme_list)} supported targets, listed identically twice, all accepted by the "
          f"compiler; {len(accepted - readme_list)} accepted-but-unsupported name(s) explained; "
          f"{len(bullets)} SECURITY.md exclusion(s) resolve to the rule")
sys.exit(1 if bad else 0)
PY
[[ $? -eq 0 ]] || failed=$((failed+1))

# ---------------------------------------------------------------
# 8. no rule identifier is defined twice
# ---------------------------------------------------------------
# A rule is DEFINED by a line-start bold identifier - `**MM-ALLOC-16a
# (H).**`, `**ERR-REC-6 (H).**`, `**MAC-CAP-10.3 - ...**` - and the
# fifteen memory-model invariants by their table row, `| **I8** |`.
# Every other appearance of an id is a citation, which is supposed to
# repeat.
#
# THE FLOOR IS WHAT KEEPS THIS FROM GOING VACUOUS. A regex that stopped
# matching would find no duplicates and report success, which is this
# repository's most common defect. 274 definitions on 2026-08-31 across
# three documents; the floor is 200, low enough that ordinary editing
# does not trip it and high enough that a broken pattern cannot pass.
#
# THE ABLATION, run 2026-08-31 against `docs/memory-model.md` as it
# stood at `9116167`, before the renumbering:
#
#     FAIL rules: docs/memory-model.md defines `MM-ALLOC-17` 2 times ...
#     FAIL rules: docs/memory-model.md defines `MM-LIFE-2e` 2 times ...
#     FAIL rules: docs/memory-model.md defines `MM-LIFE-2f` 2 times ...
#
# and the section exits 1. It is green only against the repaired
# document.
echo "== documents: no rule identifier is defined twice =="
if ! python3 - $(gate_prose_docs) <<'RULEIDS'
import collections, os, re, sys

# `MM-ALLOC-16a`, `ERR-REC-6`, `MAC-CAP-10.3` - two or more
# dash-separated upper-case segments, then a number, then an optional
# dotted sub-number and an optional letter suffix. The dotted form is
# load-bearing: without it `MAC-CAP-10.1` through `10.6` all truncate to
# `MAC-CAP-10` and this check invents six duplicates that do not exist.
RULE = re.compile(r"^\*\*(?P<id>[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+-[0-9]+(?:\.[0-9]+)*[a-z]?)\b", re.M)
# The memory model's invariants live in a table, not in prose headers.
INV = re.compile(r"^\| \*\*(?P<id>I[0-9]+)\*\*", re.M)

bad = 0
total = 0
for doc in sys.argv[1:]:
    if not os.path.exists(doc):
        print(f"FAIL rules: {doc} is in the prose-document list and does not exist")
        bad += 1
        continue
    text = open(doc, encoding="utf-8").read()
    where = collections.defaultdict(list)
    for pat in (RULE, INV):
        for m in pat.finditer(text):
            where[m.group("id")].append(text.count("\n", 0, m.start()) + 1)
    total += sum(len(v) for v in where.values())
    for rid, lines in sorted(where.items()):
        if len(lines) > 1:
            print(f"FAIL rules: {doc} defines `{rid}` {len(lines)} times, at lines "
                  f"{', '.join(str(n) for n in lines)} - a rule id is never reused "
                  f"(memory-model.md 0.1), and every citation of it resolves to "
                  f"whichever definition the reader happens to find first")
            bad += 1
if total < 200:
    print(f"FAIL rules: only {total} rule definitions found across the prose documents; "
          f"the floor is 200 (274 on 2026-08-31). The pattern has stopped matching, and "
          f"a pattern that matches nothing finds no duplicates")
    bad += 1
elif not bad:
    print(f"ok   {total} rule definitions, each identifier defined exactly once")
sys.exit(1 if bad else 0)
RULEIDS
then failed=$((failed+1)); fi

echo
if (( failed )); then
  echo "check-doc-drift: $failed section(s) failed"
  exit 1
fi
echo "check-doc-drift: registry, counts, status rows, fixture paths, case"
echo "                 numbering, the diagnostic showcase, the target list and the"
echo "                 rule-identifier namespace all agree with the tree"
