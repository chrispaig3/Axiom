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
#      It is 39/39 today. `check-tools-selfhost.sh` already checks
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
#   4  EVERY tests/ PATH NAMED IN THE DOCS EXISTS.
# ---------------------------------------------------------------------
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1
axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

echo "== building the compiler under test from self_host/ =="
if ! "$axiom" build --input self_host/main.ax -o "$work/axc" > "$work/build.log" 2>&1; then
  echo "FAIL: could not build the compiler under test"; head -20 "$work/build.log"; exit 1
fi
axc="$work/axc"

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
if (( nc < 35 )); then
  echo "FAIL: only $nc constructed codes found; the floor is 35 (the grep stopped matching)"
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
# 2, 3, 4 - the documents themselves
# ---------------------------------------------------------------
python3 - "$repo_root" <<'PY'
import os, re, sys, glob
root = sys.argv[1]
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
for doc in ("README.md", "docs/reference.md", "CONTRIBUTING.md",
            "docs/v1-roadmap.md", "docs/self-hosting.md", "docs/macros.md"):
    # The extension alternation needs the boundary: without it
    # `tests/fmt/parity/170-empty-tuple.axp` matched as `...ax` and was
    # reported missing, which is a gate finding its own bug and calling
    # it drift. Caught on this gate's first run.
    named |= set(re.findall(r"tests/[\w./-]+\.(?:axbad|axp|ax|py|sh|out|golden)(?![\w])",
                            open(doc, encoding="utf-8").read()))
if len(named) < 40:
    print(f"FAIL paths: only {len(named)} tests/ paths named across the docs; floor is 40")
    bad += 1
missing = sorted(p for p in named if not os.path.exists(p))
if missing:
    for p in missing:
        print(f"FAIL paths: the docs name {p}, which does not exist")
    bad += len(missing)
else:
    print(f"ok   all {len(named)} tests/ paths named in the docs exist")

sys.exit(1 if bad else 0)
PY
[[ $? -eq 0 ]] || failed=$((failed+1))

echo
if (( failed )); then
  echo "check-doc-drift: $failed section(s) failed"
  exit 1
fi
echo "check-doc-drift: registry, counts, status rows and fixture paths all agree with the tree"
