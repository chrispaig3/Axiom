#!/usr/bin/env python3
"""The repository's `.ax` census: the TRACKED set, not the working tree.

WHY THIS IS A FILE AND NOT THREE LINES INSIDE THE GATE.

`scripts/check-doc-drift.sh` recomputes every count the prose documents
state, and one of them is "N `.ax` files in the repo". It computed that
with `glob("**/*.ax", recursive=True)`, and it runs in
`run-gates.sh`'s PARALLEL phase, six gates at a time - so whatever any
sibling had momentarily written into the tree was counted. Measured
2026-09-03: 616 in the battery against 613 run alone, while CI stayed
green because `ci.yml` runs the gate as its own sequential step. A
local battery that is unreliable for a reason CI cannot reproduce is
the worst kind of flake, because the fix is never obvious from the
failure.

A hunt for the culprit gate came back EMPTY. All 54 gates of the
parallel phase were run under a 0.1 s watcher over the tree and not one
of them created a `.ax` inside it. The mechanism that WAS reproduced is
plainer: an untracked `.ax` sitting in the working tree - a scratch
file, an editor's, a concurrent agent's - and with one present the gate
printed `says 613 .ax files, measured 614`.

So the fix is neither to serialise the gate nor to keep hunting. It is
to ask a question whose answer does not depend on what else is
happening in the directory: `git ls-files` reads the INDEX. Measured on
a clean tree the same day, `git ls-files '*.ax'` = 613, the glob = 613,
and a `diff` of the two sorted lists is EMPTY - the substitution changes
the answer in no case except the one it exists for.

AND IT LIVES HERE, IN ITS OWN FILE, SO THE ABLATION CAN DRIVE IT. The
repository's rule about probes is that a probe has to drive the path the
gate drives - `check-compat.sh` carries the scar from a probe that
tested a function while the defect was at the call site. An ablation
that re-implemented this census in a synthetic repository would be
testing its own copy. `check-doc-drift.sh` section 9 runs THIS PROGRAM
against a synthetic repository instead, so the thing measured and the
thing shipped are one file.

IT FAILS LOUDLY RATHER THAN FALLING BACK. A `git` that will not answer
must not silently return the glob: that reintroduces the race in the
one configuration nobody tests, and reads as success. Exit 1 with the
reason on stderr instead.

Output, on stdout:

    <count>
    strays: <path> <path> ...      (only when there are untracked ones)

The strays line exists because `git ls-files` reads the index, and a
contributor who writes a new fixture without `git add`ing it will see
this count NOT move. That is the correct failure direction - loud, in
CI, where the file IS tracked - but it is a real ergonomic change, and
the note is what tells them why before CI does.

Usage:  scripts/lib/ax-census.py [<directory>]
"""
import os
import subprocess
import sys
import glob

root = sys.argv[1] if len(sys.argv) > 1 else "."
os.chdir(root)

r = subprocess.run(["git", "ls-files", "-z", "--", "*.ax"],
                   capture_output=True, text=True)
if r.returncode != 0:
    sys.stderr.write(
        "the .ax census needs a git checkout - `git ls-files` exited "
        f"{r.returncode}: {r.stderr.strip()[:300]}\n")
    sys.exit(1)

tracked = {p for p in r.stdout.split("\0") if p}
print(len(tracked))

strays = sorted(set(glob.glob("**/*.ax", recursive=True)) - tracked)
if strays:
    print("strays: " + " ".join(strays))
