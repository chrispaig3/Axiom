#!/usr/bin/env bash
# The Windows entry shim's parsers, executed on this host.
#
# `mainCRTStartup` (self_host/codegen.ax, `emitWinEntry`) narrows the
# UTF-16 command line and environment to UTF-8 and lays them out as the
# POSIX vector `Sys.ax` reads. The split follows `CommandLineToArgvW`'s
# rules. A wrong rule yields a plausible argv, not a crash: a path split
# at its space, a trailing backslash eaten, a `""` dropped.
#
# The parsers are plain loads and stores in functions that call only
# each other, so this gate cuts the `@__axiom_win_*` helpers out of the
# windows-x86_64 and windows-aarch64 modules, assembles them for the
# host and runs them from a C harness against known answers. The
# harness may use libc, since it isn't Axiom's output. The kernel32
# calls themselves need a Windows machine
# (`check-windows-hello.sh --run`), which no CI job provides.
#
# Negative probes ablate two rules in the extracted IR. The harness must
# then disagree with the golden on the cases that use them, or the gate
# would only show that the harness ran.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

status=0

# The modules the helpers are cut from, one per Windows target. Any
# program with an entry carries them, and the hello case is the
# smallest. Both architectures emit the same plain-IR shim, and both
# are run, so one target's emission bending it fails the golden.
win_targets=(windows-x86_64 windows-aarch64)
for t in "${win_targets[@]}"; do
  if ! "$axc" --target="$t" emit-llvm tests/stdlib/010-hello.ax -o "$work/win-$t.ll" >"$work/emit.log" 2>&1; then
    echo "FAIL: could not emit tests/stdlib/010-hello.ax for $t"
    sed 's/^/    /' "$work/emit.log" | head -5
    exit 1
  fi
done

# Cut every `define internal i64 @__axiom_win_...` through its closing
# brace, drop `internal` so the harness can name them, and use the
# host's triple. The module's `attributes #0` comes too: its
# `no-builtins` stops the host's optimiser turning the narrowing loop
# into a libc call.
host_triple="$(llc --version | sed -n 's/.*Default target: *//p' | head -1)"
if [[ -z "$host_triple" ]]; then
  echo "FAIL: could not read the host triple from \`llc --version\`"
  exit 1
fi
extract_shim() {
  echo "target triple = \"$host_triple\""
  awk '
    /^define internal i64 @__axiom_win_/ { sub(/^define internal /, "define "); keep = 1 }
    keep { print }
    keep && /^}/ { keep = 0; print "" }
  ' "$1"
  grep '^attributes #0' "$1"
}
for t in "${win_targets[@]}"; do
  extract_shim "$work/win-$t.ll" > "$work/shim-$t.ll"
  nfun="$(grep -c '^define i64 @__axiom_win_' "$work/shim-$t.ll" || true)"
  if [[ "$nfun" -ne 6 ]]; then
    echo "FAIL: cut $nfun \`__axiom_win_*\` helpers out of the $t module; the entry shim emits 6"
    echo "     (wlen, put, narrow, args, blocklen, env) - the emitter moved and this gate stopped reading it"
    exit 1
  fi
done
# The negative probes below ablate the windows-x86_64 copy.
cp "$work/shim-windows-x86_64.ll" "$work/shim.ll"

# The harness. `u""` literals are UTF-16 under both clang and gcc, and
# `char16_t` is spelled out because macOS ships no <uchar.h>. Each case
# prints `argc=N` and then one `[arg]` line per argument. An environment
# block prints `envc=N units=U` and then its entries.
cat > "$work/harness.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
typedef unsigned short char16_t;
extern long __axiom_win_wlen(long p);
extern long __axiom_win_args(long cmd, long vec, long strs, long scratch);
extern long __axiom_win_env(long blk, long vec, long strs);
extern long __axiom_win_blocklen(long blk);
static void show_args(const char16_t *cmd) {
    long clen = __axiom_win_wlen((long)cmd);
    char *scratch = calloc(2 * (clen + 1) + 16, 1);
    long argc = __axiom_win_args((long)cmd, 0, 0, (long)scratch);
    long *vec = calloc(argc + 2, sizeof(long));
    char *strs = calloc(4 * clen + 16, 1);
    long argc2 = __axiom_win_args((long)cmd, (long)vec, (long)strs, (long)scratch);
    printf("argc=%ld", argc);
    if (argc2 != argc) printf(" MISMATCH(count %ld, fill %ld)", argc, argc2);
    printf("\n");
    for (long i = 0; i < argc2; i++) printf("[%s]\n", (const char *)vec[i]);
    free(scratch); free(vec); free(strs);
}
static void show_env(const char16_t *blk) {
    long units = __axiom_win_blocklen((long)blk);
    long n = __axiom_win_env((long)blk, 0, 0);
    long *vec = calloc(n + 2, sizeof(long));
    char *strs = calloc(4 * units + 16, 1);
    long n2 = __axiom_win_env((long)blk, (long)vec, (long)strs);
    printf("envc=%ld units=%ld", n2, units);
    if (n2 != n) printf(" MISMATCH(count %ld, fill %ld)", n, n2);
    printf("\n");
    for (long i = 0; i < n2; i++) printf("[%s]\n", (const char *)vec[i]);
    free(vec); free(strs);
}
int main(void) {
    show_args(u"prog.exe a b");                       /* 1 plain */
    show_args(u"\"C:\\Program Files\\x.exe\" \"a b\" c"); /* 2 quoted program name and argument */
    show_args(u"p \\\"q\\\" r");                      /* 3 odd backslash escapes the quote */
    show_args(u"p \"a\\\\\" b");                      /* 4 even backslashes before a closing quote */
    show_args(u"p a\\\\\\\\b");                       /* 5 backslashes not before a quote are literal */
    show_args(u"p \"a\"\"b\"");                       /* 6 a \"\" inside quotes is one quote */
    show_args(u"p \"\"");                             /* 7 the empty argument */
    show_args(u"p a\tb");                             /* 8 tab delimits */
    show_args(u"p \"unterminated");                   /* 9 an open quote runs to the end */
    show_args(u"p \xe9 \U0001D11E");                  /* 10 two- and four-byte UTF-8, via a surrogate pair */
    show_args(u"p \xD800x");                          /* 11 a lone surrogate is U+FFFD */
    show_args(u"");                                   /* 12 no command line: argc 0 */
    show_args(u"p a  ");                              /* 13 trailing whitespace adds nothing */
    show_args(u"p a \"\" b");                         /* 14 an empty argument between two */
    show_args(u"\"quoted prog\"tail a");              /* 15 the program name's quote is a delimiter, not an escape */
    show_args(u"p \"x\"y\"z\"");                      /* 16 quotes toggle mid-argument */
    show_args(u"p \\\\\\\"q");                        /* 17 three backslashes and a quote */
    show_env(u"A=1\0BB=22\0=C:=C:\\x\0\0");           /* the drive-cwd entries Windows adds begin with `=` */
    show_env(u"\0");                                  /* an empty block */
    return 0;
}
C

# The golden: what the rules produce for each harness case, in order.
# The two non-ASCII lines hold the UTF-8 of U+00E9, U+1D11E and U+FFFD
# as octal escapes.
printf 'argc=3\n[prog.exe]\n[a]\n[b]\n' > "$work/expected"
printf 'argc=3\n[C:\\Program Files\\x.exe]\n[a b]\n[c]\n' >> "$work/expected"
printf 'argc=3\n[p]\n["q"]\n[r]\n' >> "$work/expected"
printf 'argc=3\n[p]\n[a\\]\n[b]\n' >> "$work/expected"
printf 'argc=2\n[p]\n[a\\\\\\\\b]\n' >> "$work/expected"
printf 'argc=2\n[p]\n[a"b]\n' >> "$work/expected"
printf 'argc=2\n[p]\n[]\n' >> "$work/expected"
printf 'argc=3\n[p]\n[a]\n[b]\n' >> "$work/expected"
printf 'argc=2\n[p]\n[unterminated]\n' >> "$work/expected"
printf 'argc=3\n[p]\n[\303\251]\n[\360\235\204\236]\n' >> "$work/expected"
printf 'argc=2\n[p]\n[\357\277\275x]\n' >> "$work/expected"
printf 'argc=0\n' >> "$work/expected"
printf 'argc=2\n[p]\n[a]\n' >> "$work/expected"
printf 'argc=4\n[p]\n[a]\n[]\n[b]\n' >> "$work/expected"
printf 'argc=3\n[quoted prog]\n[tail]\n[a]\n' >> "$work/expected"
printf 'argc=2\n[p]\n[xyz]\n' >> "$work/expected"
printf 'argc=2\n[p]\n[\\"q]\n' >> "$work/expected"
printf 'envc=3 units=20\n[A=1]\n[BB=22]\n[=C:=C:\\x]\n' >> "$work/expected"
printf 'envc=0 units=1\n' >> "$work/expected"

# Assemble the shim for the host, at the driver's default level and at
# -O2: the state cells are `alloca`s that mem2reg promotes above -O0,
# so both shapes of the code are run.
run_harness() {  # <shim.ll> <label> -> writes $work/<label>.out, prints nothing on success
  local shim="$1" label="$2"
  llc -filetype=obj -O1 -relocation-model=pic "$shim" -o "$work/$label.o1.o" 2>"$work/$label.llc.err" || return 1
  opt -O2 "$shim" -S -o "$work/$label.opt.ll" 2>/dev/null \
    && llc -filetype=obj -O2 -relocation-model=pic "$work/$label.opt.ll" -o "$work/$label.o2.o" 2>>"$work/$label.llc.err" || return 1
  cc -o "$work/$label.bin1" "$work/harness.c" "$work/$label.o1.o" 2>"$work/$label.cc.err" || return 1
  cc -o "$work/$label.bin2" "$work/harness.c" "$work/$label.o2.o" 2>>"$work/$label.cc.err" || return 1
  "$work/$label.bin1" > "$work/$label.out1" 2>&1 || return 1
  "$work/$label.bin2" > "$work/$label.out2" 2>&1 || return 1
  cmp -s "$work/$label.out1" "$work/$label.out2" || { echo "    -O1 and -O2 builds disagree"; return 1; }
  cp "$work/$label.out1" "$work/$label.out"
}

cases="$(grep -c '^argc=\|^envc=' "$work/expected")"
for t in "${win_targets[@]}"; do
  if run_harness "$work/shim-$t.ll" "real-$t" && cmp -s "$work/real-$t.out" "$work/expected"; then
    echo "ok   the $t entry shim's parsers answer all $cases cases on $host_triple, at -O1 and -O2"
  else
    echo "FAIL the $t entry shim's parsers do not answer the golden"
    { diff "$work/expected" "$work/real-$t.out" 2>/dev/null || true; } | head -20 | sed 's/^/    /'
    for f in "real-$t.llc.err" "real-$t.cc.err"; do [[ -s "$work/$f" ]] && head -5 "$work/$f" | sed 's/^/    /'; done
    status=1
  fi
done

# ---------------------------------------------------------------
# Negative probes: a wrong rule is visible, and only on its own cases.
# ---------------------------------------------------------------
# 1. The `""`-inside-quotes rule: its comparison against 34 (`"`)
#    becomes one against 35, so `"a""b"` is read the old-msvcrt way.
#    Case 6 must move and nothing else.
sed 's/%nxtq = icmp eq i64 %nxt, 34/%nxtq = icmp eq i64 %nxt, 35/' "$work/shim.ll" > "$work/abl1.ll"
if cmp -s "$work/abl1.ll" "$work/shim.ll"; then
  echo "FAIL negative probe: the \`\"\"\` rule's comparison is not where this probe looks; the ablation changed nothing"
  status=1
elif run_harness "$work/abl1.ll" abl1 && ! cmp -s "$work/abl1.out" "$work/expected"; then
  moved="$(diff "$work/expected" "$work/abl1.out" | grep -c '^[<>]' || true)"
  if grep -q '^> \[a\]$' <(diff "$work/expected" "$work/abl1.out") ; then
    echo "ok   negative probe: ablating the \`\"\"\` rule moves the golden ($moved lines, case 6 reads \`a\` then \`b\`)"
  else
    echo "ok   negative probe: ablating the \`\"\"\` rule moves the golden ($moved lines)"
  fi
else
  echo "FAIL negative probe: the \`\"\"\` rule ablated and the harness still answered the golden (or did not run)"
  status=1
fi

# 2. The odd-backslash rule: `icmp ne` becomes `icmp eq`, so an odd run
#    before a quote no longer escapes it. Cases 3 and 17 must move.
sed 's/%isodd = icmp ne i64 %odd, 0/%isodd = icmp eq i64 %odd, 0/' "$work/shim.ll" > "$work/abl2.ll"
if cmp -s "$work/abl2.ll" "$work/shim.ll"; then
  echo "FAIL negative probe: the odd-backslash rule's comparison is not where this probe looks; the ablation changed nothing"
  status=1
elif run_harness "$work/abl2.ll" abl2 && ! cmp -s "$work/abl2.out" "$work/expected"; then
  moved="$(diff "$work/expected" "$work/abl2.out" | grep -c '^[<>]' || true)"
  echo "ok   negative probe: ablating the odd-backslash rule moves the golden ($moved lines)"
else
  echo "FAIL negative probe: the odd-backslash rule ablated and the harness still answered the golden (or did not run)"
  status=1
fi

exit "$status"
