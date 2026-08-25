#!/usr/bin/env bash
# Assert that this repository's TWO tables of syscall numbers agree.
#
# There are two, and they are two copies of one fact:
#
#   1. `self_host/codegen.ax` carries `targetMmapNum`, `targetExitNum`
#      and `targetWriteNum` - the numbers the EMITTED RUNTIME uses.
#      Every program the compiler produces contains them: the allocator
#      and the arena map their chunks with one, and three abort paths -
#      allocator OOM, division by zero, and an unhandled effect - write
#      a line to fd 2 and exit through the other two.
#
#   2. `stdlib/Sys/Platform.{darwin,linux-aarch64,linux-x86_64}.ax`
#      carry the same syscalls for the STANDARD LIBRARY, as `sysExit`,
#      `sysWrite` and their neighbours.
#
# Nothing compared them, and they had already disagreed. The comment
# above `targetExitNum` in `self_host/codegen.ax` records it: the
# emitted abort paths exited through Linux `exit` (93 on aarch64, 60 on
# x86-64) while the platform modules exit through `exit_group` (94 and
# 231) - and `Platform.linux-aarch64.ax` states the rule in as many
# words, "exit_group (94), not exit (93)", while the compiler emitted 93
# anyway. It was latent, because `exit` ends the calling thread and
# nothing Axiom emits has a second one; it stops being latent the moment
# one of these programs has two threads, and the failure then is a
# process that aborts and stays alive. It is fixed. Nothing stopped it
# from recurring, and three abort paths ride on it.
#
# HOW THE TWO TABLES ARE READ, and why it is not `grep`.
#
# Both come out of ONE `emit-llvm` per target, and neither is a second
# parse of the source:
#
#   * the emitted runtime's numbers are read from the `asm sideeffect`
#     syscall sites in the module - the literal operands the compiler
#     wrote, which is what the kernel will be handed;
#   * the standard library's numbers are read from the bodies of
#     `@Sys.Platform$sysExit`, `@Sys.Platform$sysWrite` and their
#     neighbours in the SAME module (`ret i64 94`), because the compiler
#     emits the whole selected platform module whether or not the
#     program calls into it.
#
# Parsing the two sources instead would be brittle in both directions
# and brittle in the direction that stays green: the codegen table is a
# chain of `(if (== t 2) ...)` arms whose target codes are assigned
# somewhere else in the file, the platform table is one
# `(pub fn (sysExit) 94)` per constant, and a pattern that silently
# matched nothing would report agreement. Reading the emitted module
# reads the value the compiler actually SELECTS for a target, which
# includes the platform-module resolution: `Platform.darwin.ax` serves
# both darwin targets because no `.darwin-aarch64.ax` exists, and this
# gate never has to know that. A table that went missing surfaces here
# as a missing symbol or a missing syscall site, not as silence.
#
# WHAT THIS GATE DOES NOT SAY. It asserts AGREEMENT, not correctness:
# two tables edited to the same wrong number pass it. What the numbers
# should BE is pinned by the platform modules' own prose and, in the
# end, by the CI matrix running these programs on the real kernels.
#
# WHAT IS COMPARED: every syscall named in both tables - `exit` and
# `write` today. `mmap` is emitted-only, because nothing in the standard
# library maps memory, so there is no second copy to compare it
# against; the guard for that is in the report below and fails the day
# `Sys.Platform` grows an mmap number without this gate being told, so
# the intersection cannot quietly shrink out from under the comparison.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# The subject is `self_host/codegen.ax`'s table, so the compiler that
# emits the probe has to be built from THIS tree. Using `$axiom` - which
# may be a seed-descended binary older than the change under test -
# would make an edit to the codegen table invisible to the gate that
# exists to watch it. About eight seconds.
gate_build_axc axc

targets=(darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64)

# Which platform module serves a target, for the failure message to
# name. The mapping is `targetOsArchSuffix` then `targetOsSuffix` in
# `self_host/codegen.ax`: `.{os}-{arch}.ax` if it exists, otherwise
# `.{os}.ax`. Only the linux modules are split by arch today.
platform_file() {
  case "$1" in
    darwin-*) echo "stdlib/Sys/Platform.darwin.ax" ;;
    *)        echo "stdlib/Sys/Platform.$1.ax" ;;
  esac
}

# ...and the mapping above must stay true, or every message this gate
# prints names the wrong file. A more specific module out-ranks the one
# named here, so its appearance is what would make the mapping a lie.
for target in "${targets[@]}"; do
  pf="$(platform_file "$target")"
  if [[ ! -f "$pf" ]]; then
    echo "FAIL [$target]: this gate names $pf, which does not exist" >&2
    exit 1
  fi
  if [[ "$pf" != "stdlib/Sys/Platform.$target.ax" && -f "stdlib/Sys/Platform.$target.ax" ]]; then
    echo "FAIL [$target]: stdlib/Sys/Platform.$target.ax now exists and out-ranks $pf;" >&2
    echo "     update platform_file() in this script before trusting its messages" >&2
    exit 1
  fi
done

# The probe. Three properties of it are load-bearing:
#
#   * it imports `Sys.Platform` and NOTHING ELSE. Nothing in that module
#     performs a syscall - it is constants - so every `asm sideeffect`
#     in the emitted module is one the BACKEND wrote. Importing `Sys`
#     would mix the standard library's own `__syscallN` sites into the
#     same file and the classifier below could no longer tell whose
#     number it was reading.
#   * it declares an effect. `__axiom_unhandled_effect` - the third of
#     the three abort paths - is emitted only for a program that
#     declares one (`emitEffectGlobals` calls `emitUnhandledTrap` when
#     the effect table is non-empty), so without this the gate would
#     compare two of the three exits and say nothing about the third.
#   * `main` names the two constants under test, so a rename in
#     `Sys.Platform` fails the probe's own compile with a diagnostic
#     instead of quietly removing a comparison.
probe="$work/platform-constants-probe.ax"
cat > "$probe" <<'PROBE'
(import Sys.Platform)

(effect Probe
  (probeOp :: (-> Int Int)))

(:: main Int)

(fn (main) (+ (sysExit) (sysWrite)))
PROBE

# Compare one emitted module's two tables, printing one `ok`/`FAIL` line
# per syscall. A function rather than an inline pipeline for the same
# reason `absolute_violations` is one in check-cross-targets.sh: the
# negative probes at the end drive it with deliberately broken modules,
# and a verdict that is never itself tested is the failure mode this
# repository has already been bitten by.
#
# It always exits 0 and reports through its OUTPUT. `set -e` does not
# spare a command substitution, so a helper that exited non-zero on the
# violation it was asked to print would take the gate down one line
# before its own result - which is the hazard check-freestanding.sh
# records having hit.
platform_table_report() {
  local target="$1" ir="$2" platfile="$3"
  awk -v target="$target" -v platfile="$platfile" '
    BEGIN {
      # syscall -> the `Sys.Platform` constant it must equal, and the
      # `self_host/codegen.ax` function carrying the emitted copy.
      # A "-" counterpart means emitted-only, deliberately; the END
      # block below is what keeps that claim honest.
      std_of["exit"]  = "sysExit";  cg_of["exit"]  = "targetExitNum"
      std_of["write"] = "sysWrite"; cg_of["write"] = "targetWriteNum"
      std_of["mmap"]  = "-";        cg_of["mmap"]  = "targetMmapNum"

      # The census of syscall sites the emitted runtime contains today,
      # as a floor. Three exits: allocator OOM (status 70), an unhandled
      # effect (71), division by zero (72). Writes: the three trap
      # messages, plus the six the backtracer makes - a header, and per
      # frame the `  at ` prefix, the name or `<unknown>`, and a
      # newline. Two mmaps: the allocator and the arena. A path that
      # DISAPPEARS takes the comparison with it and must be noticed; a
      # path that is ADDED passes the floor and is compared like the
      # rest, which is why the write floor is left at the number the
      # traps alone need rather than raised to the count of the day.
      floor_of["exit"] = 3
      floor_of["write"] = 2
      floor_of["mmap"] = 2
    }

    # Track the enclosing definition, and arm the reader when it is one
    # of the platform constants.
    /^define / {
      fn = $0
      sub(/^.*@/, "", fn)
      sub(/\(.*$/, "", fn)
      pending = ""
      if (fn ~ /^Sys\.Platform\$/) pending = substr(fn, index(fn, "$") + 1)
      next
    }

    # The copy in the standard library: the constant a platform module
    # compiles to. Only a literal counts - a constant that stopped being
    # one is reported as absent below rather than read as zero.
    pending != "" && $1 == "ret" {
      if ($3 ~ /^-?[0-9]+$/) stdval[pending] = $3
      pending = ""
      next
    }

    # The copy in the backend: the operands of an emitted syscall.
    /asm sideeffect/ {
      # Everything after the LAST quote on the line. The two quoted
      # strings are the asm template and its constraint list; no operand
      # and no argument ever contains a quote, so this splits the
      # instruction from its arguments without parsing either string.
      q = 0
      for (i = length($0); i > 0; i--)
        if (substr($0, i, 1) == "\"") { q = i; break }
      args = substr($0, q + 1)
      gsub(/[()]/, "", args)
      gsub(/i64/, "", args)
      gsub(/ /, "", args)
      n = split(args, a, ",")

      # WHICH syscall this is, decided by its ARGUMENTS. The number is
      # the thing under test and so cannot also be the label: reading
      # "94 means exit" out of a table would make this gate compare the
      # codegen table against itself. mmap is the only one passing fd
      # -1; a runtime write goes to fd 2 with a pointer behind it; an
      # exit passes a status and then six zeros.
      name = "?"
      if (n == 7 && a[6] == "-1") {
        name = "mmap"
      } else if (n == 7 && a[2] == "2" && substr(a[3], 1, 1) == "%") {
        name = "write"
      } else if (n == 7 && a[3] == "0" && a[4] == "0" && a[5] == "0" &&
                 a[6] == "0" && a[7] == "0") {
        name = "exit"
      } else if (args == "") {
        # NOT A SYSCALL AT ALL. `targetFrameAsm` reads the frame
        # pointer out of x29 or %rbp for the backtracer - one
        # instruction, one output register, NO arguments and no
        # syscall number. It reached this gate as an unclassifiable
        # syscall the day it was added, which is the gate working:
        # the census below is a floor, and an asm site nobody read
        # would be a syscall nobody compared.
        #
        # The arm is deliberately narrow. An empty argument list is
        # the one shape that cannot be a syscall on any of the four
        # targets, because every one of them passes the number as the
        # first operand. A template with arguments this gate does not
        # recognise still fails, as it must.
        name = "-";
        notsys++
        next
      } else if ($0 !~ /svc #|syscall/) {
        # ALSO NOT A SYSCALL, decided by the INSTRUCTION rather than by
        # the argument shape. The longjmp half of a recovery point
        # (`targetRecoverJumpAsm`) restores a stack pointer, a frame
        # pointer and a branch target from four REGISTERS - it makes no
        # syscall, and the arm above cannot see that, because its
        # argument list is not empty.
        #
        # `svc` on AArch64 and `syscall` on x86-64 are the only two
        # instructions that can make a syscall on the four targets, and
        # `check-cross-targets.sh` already asserts that every syscall
        # template carries one of them - that is the same discriminator
        # this arm reads, so the two gates agree on what a syscall
        # template is rather than each guessing. A template that DOES
        # carry one and whose arguments this gate does not recognise
        # still fails, as it must.
        name = "-";
        notsys++
        next
      }

      if (name == "?") {
        printf "FAIL [%s] the emitted runtime makes a syscall this gate cannot classify,\n", target
        printf "     in @%s: (%s). Teach the classifier - an unread syscall is an\n", fn, args
        printf "     uncompared one, and this gate would report agreement without it.\n"
        next
      }
      count[name]++
      site[name] = site[name] " " a[1] "@" fn
      next
    }

    END {
      # Fixed order, because `for (x in array)` has none and a gate
      # whose output reorders itself is a gate nobody diffs.
      nn = split("mmap exit write", ord, " ")
      for (i = 1; i <= nn; i++) {
        name = ord[i]
        sn = std_of[name]

        if (count[name] < floor_of[name]) {
          printf "FAIL [%s] %s: the emitted runtime has %d site(s), against a census of %d.\n", \
                 target, name, count[name] + 0, floor_of[name]
          printf "     An abort path or an allocator mapping has gone, and what this\n"
          printf "     gate compares went with it.\n"
          continue
        }

        # Every site of one syscall must carry ONE number. Against a
        # standard-library counterpart that follows from comparing each
        # site to it; mmap has none, so it is stated here.
        m = split(site[name], sv, " ")
        first = ""
        split_ok = 1
        for (j = 1; j <= m; j++) {
          split(sv[j], p, "@")
          if (first == "") first = p[1]
          else if (p[1] != first) {
            printf "FAIL [%s] %s: the emitted runtime uses %s in @%s and %s elsewhere;\n", \
                   target, name, p[1], p[2], first
            printf "     %s in self_host/codegen.ax answers one number per target.\n", cg_of[name]
            split_ok = 0
          }
        }
        if (!split_ok) continue

        if (sn == "-") {
          # Emitted-only, and it must STAY that way or start being
          # compared. The day `Sys.Platform` grows an mmap number is the
          # day this fact has two copies like the others, and the
          # comparison must be told rather than left to notice nothing.
          grew = ""
          for (s in stdval)
            if (tolower(s) ~ name) grew = grew " " s
          if (grew != "") {
            printf "FAIL [%s] %s: %s now defines%s, so this is no longer one copy of\n", \
                   target, name, platfile, grew
            printf "     one fact. Map it in std_of[] above so the two are compared.\n"
            continue
          }
          printf "ok   [%s] %-5s = %-9s %d emitted site(s); no Sys.Platform counterpart, by design\n", \
                 target, name, first, m
          continue
        }

        if (!(sn in stdval)) {
          printf "FAIL [%s] %s: %s exposes no integer constant `%s`, so this gate\n", \
                 target, name, platfile, sn
          printf "     read nothing to compare the emitted %s against.\n", first
          continue
        }

        disagreed = 0
        for (j = 1; j <= m; j++) {
          split(sv[j], p, "@")
          if (p[1] != stdval[sn]) {
            printf "FAIL [%s] %s: the emitted runtime uses %s in @%s, Sys.Platform.%s is %s\n", \
                   target, name, p[1], p[2], sn, stdval[sn]
            printf "     %s in self_host/codegen.ax vs %s - one fact, two copies,\n", \
                   cg_of[name], platfile
            printf "     and they now disagree the way `exit` and `exit_group` once did.\n"
            disagreed = 1
          }
        }
        if (!disagreed)
          printf "ok   [%s] %-5s = %-9s %d emitted site(s) and Sys.Platform.%s agree\n", \
                 target, name, first, m, sn
      }
    }
  ' "$ir"
}

status=0

for target in "${targets[@]}"; do
  ir="$work/$target.ll"
  if ! "$axc" --target="$target" emit-llvm "$probe" -o "$ir" >"$work/emit.log" 2>&1; then
    echo "FAIL [$target]: emit-llvm refused the probe"
    sed 's/^/    /' "$work/emit.log" | head -8
    status=1
    continue
  fi
  report="$(platform_table_report "$target" "$ir" "$(platform_file "$target")")"
  printf '%s\n' "$report"
  # `if`, not `&& status=1`: a failing `grep -q` at the end of an `&&`
  # list is the whole list failing, and `set -e` would end the run
  # there - on the targets that PASS.
  if grep -q '^FAIL' <<< "$report"; then
    status=1
  fi
done

# ---------------------------------------------------------------
# Negative probes.
#
# Everything above asserts that two numbers are equal, and equality is
# also what a classifier that matched nothing, an extractor that read no
# constants, or an empty module would report. So the comparison is shown
# FAILING, against real emitted modules with one number changed - the
# extractor, the classifier and the comparison all run for real, and the
# mutation is the only difference between the green run and the red one.
#
# linux-aarch64 is the subject because it is the target the historical
# disagreement was on.
# ---------------------------------------------------------------
echo "--- negative probes: the comparison can fail ---"

real="$work/linux-aarch64.ll"
plat="stdlib/Sys/Platform.linux-aarch64.ax"

# Rewrite the constant `@Sys.Platform$<name>` compiles to, in a copy of
# an emitted module. Probe machinery, used nowhere above.
mutate_stdlib_constant() {
  awk -v fname="$1" -v newval="$2" '
    /^define / {
      cur = $0
      sub(/^.*@/, "", cur)
      sub(/\(.*$/, "", cur)
      armed = (cur == "Sys.Platform$" fname)
    }
    armed && $1 == "ret" { sub(/ret i64 .*/, "ret i64 " newval); armed = 0 }
    { print }
  '
}

# Rewrite the number the emitted runtime exits through. An exit site is
# the one whose operands end in five zeros - a write has three after its
# length, an mmap has `-1` before its last - so this needs none of the
# numbers under test to find them.
#
# `all` rewrites every exit site, which is what a wrong `targetExitNum`
# produces: one function answers one number per target and all three
# abort paths call it. `one` rewrites the first, which is a shape
# codegen cannot produce today and is exactly what the report's
# one-number-per-target assertion exists for.
mutate_emitted_exits() {
  awk -v newval="$1" -v scope="${2:-all}" '
    /asm sideeffect/ && /i64 0, i64 0, i64 0, i64 0, i64 0\)$/ {
      if (scope == "all" || !hit) {
        sub(/\(i64 [0-9]+,/, "(i64 " newval ",")
        hit = 1
      }
    }
    { print }
  '
}

# `probe_expects <label> <ir> <regex it must report>`; the regex is
# matched against the FAIL lines only, so a probe cannot be satisfied by
# an `ok` line that happens to contain the same digits.
probe_failures=0
probe_expects() {
  local label="$1" mutated="$2" want="$3" out
  out="$(platform_table_report linux-aarch64 "$mutated" "$plat")"
  if ! grep '^FAIL' <<< "$out" | grep -qE "$want"; then
    echo "FAIL negative probe: $label"
    echo "    expected a FAIL line matching: $want"
    printf '%s\n' "$out" | sed 's/^/    /' | head -8
    probe_failures=$((probe_failures + 1))
  else
    echo "ok   negative probe: $label"
  fi
}

# 0. The control. The same helper on the UNMUTATED module of the same
#    target reports no violation, so every probe below is one edit away
#    from a green run rather than from a broken one.
if grep -q '^FAIL' <<< "$(platform_table_report linux-aarch64 "$real" "$plat")"; then
  echo "FAIL negative probe: the unmutated linux-aarch64 module already reports a violation"
  probe_failures=$((probe_failures + 1))
else
  echo "ok   negative probe: the unmutated module reports none, so the probes below isolate one edit"
fi

# 1. THE HISTORICAL BUG, reconstructed from the standard library's side:
#    `Sys.Platform.sysExit` says `exit` (93) where the emitted runtime
#    exits through `exit_group` (94).
mutate_stdlib_constant sysExit 93 < "$real" > "$work/p1.ll"
probe_expects "a platform module that says exit (93) where the runtime says exit_group (94)" \
  "$work/p1.ll" 'exit: the emitted runtime uses 94 in @.*, Sys.Platform.sysExit is 93'

# 2. And from the BACKEND's side, which is the direction it actually
#    happened in: codegen emitting 93 against a platform module that
#    says 94. All three abort paths move together, because they read
#    one `targetExitNum`.
mutate_emitted_exits 93 all < "$real" > "$work/p2.ll"
probe_expects "a runtime that exits through 93 where the platform module says 94" \
  "$work/p2.ll" 'exit: the emitted runtime uses 93 in @__axiom_[a-z_]+, Sys.Platform.sysExit is 94'

# 2b. The other assertion the report makes about the emitted side: the
#     three abort paths must exit through ONE number. Nothing in
#     codegen can produce a split today - they share a function - which
#     is why this is probed rather than waited for.
mutate_emitted_exits 93 one < "$real" > "$work/p2b.ll"
probe_expects "abort paths that exit through two different numbers" \
  "$work/p2b.ll" 'exit: the emitted runtime uses 9[34] in @__axiom_[a-z_]+ and 9[34] elsewhere'

# 3. `write` is compared too, and separately - probe 1 must not have
#    passed because the comparison flags everything.
mutate_stdlib_constant sysWrite 1 < "$real" > "$work/p3.ll"
probe_expects "a platform module carrying the x86-64 write number on aarch64" \
  "$work/p3.ll" 'write: the emitted runtime uses 64 in @.*, Sys.Platform.sysWrite is 1'

# 4. Vacuity, first direction: a module with no syscall sites at all
#    must be reported as such rather than as agreement. This is what a
#    classifier that stopped matching would look like.
grep -v 'asm sideeffect' "$real" > "$work/p4.ll"
probe_expects "an emitted runtime with no syscall sites is not agreement" \
  "$work/p4.ll" 'exit: the emitted runtime has 0 site\(s\), against a census of 3'

# 5. Vacuity, second direction: a platform constant that is no longer an
#    integer literal is absent, not zero.
mutate_stdlib_constant sysExit '%no_longer_a_constant' < "$real" > "$work/p5.ll"
probe_expects "a platform constant that stopped being one reads as absent" \
  "$work/p5.ll" 'exposes no integer constant .sysExit.'

# 6. The emitted-only claim is guarded: the day `Sys.Platform` grows an
#    mmap number, `mmap` stops being one copy of one fact and this gate
#    has to be told, rather than going on comparing nothing.
cp "$real" "$work/p6.ll"
printf 'define i64 @Sys.Platform$sysMmapNum() #0 {\n\n  ret i64 222\n}\n' >> "$work/p6.ll"
probe_expects "a Sys.Platform mmap number demands to be mapped, not ignored" \
  "$work/p6.ll" 'mmap: .* now defines sysMmapNum'

# 7. A syscall shape the classifier does not know is a FAIL, not a skip.
#    Today the emitted runtime makes exactly three kinds of call; the
#    fourth one somebody adds must not slip past uncompared. The line
#    below is an `openat`-shaped call, which matches none of the three.
awk '/asm sideeffect/ && !hit {
       print; hit = 1
       line = $0
       sub(/\(i64 [0-9-]+.*$/, "(i64 56, i64 -100, i64 %path, i64 0, i64 0, i64 0, i64 0)", line)
       print line
       next
     }
     { print }' "$real" > "$work/p7.ll"
probe_expects "an unrecognised syscall shape is reported, not skipped" \
  "$work/p7.ll" 'cannot classify'

if [[ "$probe_failures" -gt 0 ]]; then
  echo "$probe_failures negative probe(s) failed - this gate is not proven able to go red" >&2
  status=1
fi

exit "$status"
