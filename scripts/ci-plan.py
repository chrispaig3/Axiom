#!/usr/bin/env python3
"""Plan the CI gate battery: which gates run in which shard.

One source of truth. The battery used to be ~120 hand-written steps in
`.github/workflows/ci.yml`, each repeating a shard condition by hand.
Adding a gate meant editing a 1,900-line workflow and choosing a shard
by guess; the shards drifted to 194 against 77 minutes, and a separate
coverage gate existed only to catch the drift.

Now a gate joins the battery by existing: every `scripts/check-*.sh`
is discovered here and assigned exactly once, to the battery or to the
dedicated job named in SPECIAL below (a job with its own machine,
toolchain or trigger). Assignment is deterministic - same tree, same
plan, on every runner - and longest-first by the weights in
`scripts/ci-weights.json`, which `ci-run.py` results refresh.

  ci-plan.py --check                 every gate assigned exactly once
  ci-plan.py --changed FILE --shard 2
                                     this shard's gates for a change set
  ci-plan.py --changed FILE --matrix battery matrix for a change set
  ci-plan.py --changed FILE --special
                                     dedicated-job gates a change touches
  ci-plan.py --refresh-weights RESULTS...
                                     fold ci-run results into ci-weights.json
  ci-plan.py --audit [ci.yml]        coverage audit (check-ci-coverage)

Selection and reuse are one definition: with `--changed`, a gate is
planned exactly when the change set meets `ci-gate.py`'s input set
for it (or the gate is an always-run audit, or the change touches
shared infrastructure, which plans everything). An unenumerable
change set plans everything - selection only ever narrows a run it
can see whole. The nightly schedule plans the full battery, so a
selection miss is caught within a day, not at release time.

The serial set (gates whose verdict depends on wall time or a quiet
machine) is read out of `scripts/run-gates.sh`'s SERIAL_RE, never
restated: the local battery and CI must agree on it by construction.
"""
import functools
import importlib.util
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
WEIGHTS_FILE = SCRIPTS / "ci-weights.json"
DEFAULT_WEIGHT = 120

# Gates a dedicated job runs, each with the job that owns it. A gate is
# here only when the battery's shape cannot serve it: another machine
# (Windows, FreeBSD), another toolchain (cargo), a different trigger
# (the nightly lineage replay), or no compiler at all (the grammar
# gate that must be able to fail before anything builds).
SPECIAL = {
    "check-bootstrap.sh": "bootstrap",
    "check-poisoned-alloc.sh": "bootstrap",
    "check-cross-targets.sh": "cross",
    "check-windows-hello.sh": "cross+windows",
    "check-ffi.sh": "ffi",
    "check-ci-coverage.sh": "grammar",
    "check-tree-sitter.sh": "grammar",
    "check-vscode.sh": "grammar",
    "check-seed-provenance.sh": "seed-provenance",
    "check-seed-lineage.sh": "seed-lineage",
    "check-reproducible.sh": "reproducible",
}

PLATFORMS = [
    {"name": "linux-aarch64", "os": "ubuntu-24.04-arm"},
    {"name": "darwin-aarch64", "os": "macos-15"},
]
SHARDS = 6


def disk_gates() -> list[str]:
    return sorted(p.name for p in SCRIPTS.glob("check-*.sh"))


def battery_gates() -> list[str]:
    drop = os.environ.get("CI_PLAN_DROP", "")
    return [g for g in disk_gates() if g not in SPECIAL and g != drop]


def serial_gates() -> set[str]:
    """The SERIAL_RE alternation in run-gates.sh, expanded to file names."""
    src = (SCRIPTS / "run-gates.sh").read_text()
    m = re.search(r"SERIAL_RE='check-\(([a-z0-9|-]+)\)\\\.sh\$'", src)
    if not m:
        raise SystemExit("ci-plan: SERIAL_RE not found in run-gates.sh; "
                         "the serial set must stay single-sourced there")
    return {f"check-{name}.sh" for name in m.group(1).split("|")}


def _alternation(var: str) -> set[str]:
    """Gate names in one of run-gates.sh's `check-(a|b|c)` classes."""
    src = (SCRIPTS / "run-gates.sh").read_text()
    m = re.search(rf"{var}='check-\(([a-z0-9|-]+)\)\\\.sh\$'", src)
    if not m:
        raise SystemExit(f"ci-plan: {var} not found in run-gates.sh")
    return {f"check-{name}.sh" for name in m.group(1).split("|")}


def weights() -> dict[str, float]:
    """Measured seconds per gate from ci-weights.json when present,
    over the coarse classes run-gates.sh already maintains (its fast
    set answers in seconds; its expensive set is the long tail)."""
    w: dict[str, float] = {}
    for g in _alternation("FAST_RE"):
        w[g] = 15.0
    for g in _alternation("EXPENSIVE_RE"):
        w[g] = 600.0
    for g in serial_gates():
        w.setdefault(g, 300.0)
    if WEIGHTS_FILE.is_file():
        try:
            data = json.loads(WEIGHTS_FILE.read_text())
            w.update({str(k): float(v) for k, v in data.items() if float(v) > 0})
        except (ValueError, TypeError) as e:
            raise SystemExit(f"ci-plan: {WEIGHTS_FILE.name} unreadable: {e}")
    return w


def assign(gates: list[str], shards: int) -> list[list[str]]:
    """Longest-processing-time assignment: heaviest gate first onto the
    least loaded shard. Unknown gates sort as the likeliest new long
    pole (the heaviest known weight), as run-gates.sh orders them."""
    w = weights()
    unknown = max(w.values(), default=float(DEFAULT_WEIGHT))
    order = sorted(gates, key=lambda g: (-w.get(g, unknown), g))
    loads = [0.0] * shards
    out: list[list[str]] = [[] for _ in range(shards)]
    for g in order:
        i = min(range(shards), key=lambda j: (loads[j], j))
        out[i].append(g)
        loads[i] += w.get(g, DEFAULT_WEIGHT)
    return out


def plan(shards: int = SHARDS) -> list[list[str]]:
    return assign(battery_gates(), shards)


# A change here can move any gate's verdict, so it plans the whole
# battery. `scripts/` helpers count as shared; a gate's own script is
# its input through input_paths below, not through this list.
SHARED_PREFIXES = ("core/", "stdlib/", "bootstrap/", "scripts/lib/", ".github/")
SHARED_FILES = {
    "scripts/ci-plan.py", "scripts/ci-run.py", "scripts/ci-gate.py",
    "scripts/run-gates.sh", "scripts/build-shared-axc.sh", "VERSION",
}


def _is_shared(path: str) -> bool:
    if path.startswith(SHARED_PREFIXES) or path in SHARED_FILES:
        return True
    return path.startswith("scripts/") and not re.fullmatch(
        r"scripts/check-[a-z0-9-]+\.sh", path)


def _ci_gate():
    spec = importlib.util.spec_from_file_location("ci_gate", SCRIPTS / "ci-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    # input_paths re-lists the tree per gate; the tree does not move
    # during planning, so memoise the listing it starts from.
    mod.tracked_paths = functools.lru_cache(maxsize=None)(mod.tracked_paths)
    return mod


def select_gates(gates: list[str], changed: set[str] | None,
                 always_run: bool = True) -> list[str]:
    """The gates a change set can affect. None (unenumerable) and any
    shared-infrastructure touch select everything; otherwise a gate
    is selected when the change meets its ci-gate input set, or it is
    an always-run audit whose verdict is about the battery itself.

    `always_run=False` is for whole-job decisions (the dedicated
    jobs): ALWAYS_RUN is a reuse rule - never trust a recorded pass -
    not a relevance rule. A dedicated job whose gate's inputs are
    untouched need not start at all; when it does start, its gate
    still runs fresh."""
    if changed is None or any(_is_shared(p) for p in changed):
        return list(gates)
    cg = _ci_gate()
    selected = []
    for g in gates:
        # touches_gate, not an input-list intersection: the change
        # set names deleted and renamed-away paths, which the new
        # tree's file list no longer holds.
        if (always_run and g in cg.ALWAYS_RUN) or cg.touches_gate(ROOT, g, changed):
            selected.append(g)
    return selected


def selected_plan(shards: int, changed: set[str] | None) -> list[list[str]]:
    return assign(select_gates(battery_gates(), changed), shards)


def coverage_problems() -> list[str]:
    problems = []
    disk = disk_gates()
    assigned = battery_gates() + sorted(SPECIAL)
    extra_special = os.environ.get("CI_PLAN_EXTRA_SPECIAL", "")
    if extra_special:
        assigned.append(extra_special)
    for g in disk:
        if assigned.count(g) != 1:
            problems.append(f"scripts/{g} is assigned {assigned.count(g)} times, not once")
    for g in sorted(set(assigned) - set(disk)):
        problems.append(f"the plan names scripts/{g}, which is not in the tree")
    for g in sorted(serial_gates() - set(disk)):
        problems.append(f"run-gates.sh SERIAL_RE names scripts/{g}, which is not in the tree")
    shards = plan()
    flat = [g for s in shards for g in s]
    if sorted(flat) != sorted(battery_gates()):
        problems.append("the sharded plan does not reproduce the battery gate list")
    if any(not s for s in shards):
        problems.append("the plan has an empty shard")
    return problems


def audit(workflow: Path) -> list[str]:
    """Coverage for check-ci-coverage.sh: the plan covers the tree, the
    workflow executes the plan, and every SPECIAL gate is invoked by a
    real step in its owning job (read structurally, so a mention in a
    comment or a step name does not count)."""
    problems = coverage_problems()
    if not workflow.is_file():
        return problems + [f"{workflow} is missing"]
    text = workflow.read_text()

    # The battery executes through ci-run.py in the `test` job, from a
    # matrix the `scope` job plans. Read both jobs structurally (the
    # ci-steps reader, not line greps): the invocations sit inside
    # multi-line `run: |` blocks, and the same string in a comment
    # above another job must not count.
    import importlib.util as _ilu
    _spec = _ilu.spec_from_file_location("ci_steps_audit", SCRIPTS / "lib" / "ci-steps.py")
    _reader = _ilu.module_from_spec(_spec)
    _spec.loader.exec_module(_reader)
    try:
        jobs = _reader.Reader(text).node(0)["jobs"]
    except Exception as e:
        return problems + [f"scripts/lib/ci-steps.py could not read the workflow: {e}"]

    def step_runs(job):
        steps = (jobs.get(job) or {}).get("steps") or []
        return [s.get("run", "") for s in steps
                if isinstance(s, dict) and isinstance(s.get("run"), str)]

    if not any("scripts/ci-plan.py" in r and "--matrix" in r for r in step_runs("scope")):
        problems.append("the scope job never runs scripts/ci-plan.py --matrix, "
                        "so the test matrix has no plan")
    if not any("scripts/ci-plan.py" in r for r in step_runs("test")):
        problems.append("the test job never runs scripts/ci-plan.py, so the battery has no plan")
    if not any("scripts/ci-run.py" in r for r in step_runs("test")):
        problems.append("the test job never runs scripts/ci-run.py, so planned gates do not execute")

    # SPECIAL gates keep literal steps; verify with the structural
    # reader the old coverage gate used, so the same mentions that were
    # refused there are refused here.
    sys.path.insert(0, str(SCRIPTS / "lib"))
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("ci_steps", SCRIPTS / "lib" / "ci-steps.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        records = mod.read_workflow(text) if hasattr(mod, "read_workflow") else None
    except Exception:
        records = None
    if records is None:
        # Fall back to the reader's CLI, whose record format is stable.
        import subprocess
        r = subprocess.run(
            [sys.executable, str(SCRIPTS / "lib" / "ci-steps.py"), str(workflow)],
            capture_output=True, text=True)
        if r.returncode != 0:
            return problems + ["scripts/lib/ci-steps.py could not read the workflow"]
        ran = {ln.split("\t")[1] for ln in r.stdout.splitlines() if ln.startswith("RUN\t")}
    else:
        ran = {rec[1] for rec in records if rec[0] == "RUN"}
    for gate, job in sorted(SPECIAL.items()):
        if gate not in ran:
            problems.append(f"scripts/{gate} belongs to the `{job}` job and no step runs it")
    return problems


def main(argv: list[str]) -> int:
    args = argv[1:]
    shards = SHARDS
    if "--shards" in args:
        i = args.index("--shards")
        shards = int(args[i + 1])
    if "--check" in args:
        problems = coverage_problems()
        for p in problems:
            print(f"FAIL {p}")
        if not problems:
            b = battery_gates()
            print(f"ok   {len(disk_gates())} gates: {len(b)} in the battery "
                  f"({shards} shards x {len(PLATFORMS)} platforms), "
                  f"{len(SPECIAL)} in dedicated jobs, each assigned once")
            w = weights()
            loads = [round(sum(w.get(g, DEFAULT_WEIGHT) for g in s))
                     for s in plan(shards)]
            print(f"     estimated shard loads (s): {loads}")
        return 1 if problems else 0
    if "--audit" in args:
        i = args.index("--audit")
        wf = Path(args[i + 1]) if i + 1 < len(args) else ROOT / ".github/workflows/ci.yml"
        problems = audit(wf if wf.is_absolute() else ROOT / wf)
        for p in problems:
            print(p)
        return 1 if problems else 0
    if "--refresh-weights" in args:
        import statistics
        files = [a for a in args[args.index("--refresh-weights") + 1:]
                 if not a.startswith("--")]
        samples: dict[str, list[float]] = {}
        for f in files:
            for line in Path(f).read_text().splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                # Reused rows measure fingerprinting, not the gate.
                if row.get("status") == "passed" and float(row.get("seconds", 0)) > 0:
                    samples.setdefault(str(row["gate"]), []).append(float(row["seconds"]))
        known: dict[str, float] = {}
        if WEIGHTS_FILE.is_file():
            known = {str(k): float(v)
                     for k, v in json.loads(WEIGHTS_FILE.read_text()).items()}
        known.update({g: round(statistics.median(s), 1)
                      for g, s in sorted(samples.items())})
        WEIGHTS_FILE.write_text(json.dumps(known, indent=1, sort_keys=True) + "\n")
        print(f"ci-plan: {WEIGHTS_FILE.name} refreshed from "
              f"{sum(len(s) for s in samples.values())} runs of "
              f"{len(samples)} gates ({len(known)} weights known)")
        return 0
    changed: set[str] | None = None
    if "--changed" in args:
        i = args.index("--changed")
        listing = Path(args[i + 1])
        if listing.is_file():
            changed = {ln.strip() for ln in listing.read_text().splitlines() if ln.strip()}
    if "--special" in args:
        for g in select_gates(sorted(SPECIAL), changed, always_run=False):
            print(g)
        return 0
    the_plan = selected_plan(shards, changed)
    if "--platforms" in args:
        for p in PLATFORMS:
            print(p["name"])
        return 0
    if "--matrix" in args:
        include = [
            {"name": p["name"], "os": p["os"], "shard": i + 1, "shards": shards}
            for p in PLATFORMS for i, s in enumerate(the_plan) if s
        ]
        print(json.dumps({"include": include}))
        return 0
    if "--shard" in args:
        i = args.index("--shard")
        n = int(args[i + 1])
        if not 1 <= n <= shards:
            print(f"ci-plan: --shard {n} outside 1..{shards}", file=sys.stderr)
            return 2
        for g in the_plan[n - 1]:
            print(g)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
