#!/usr/bin/env bash
# The Windows entry shim's parsers, executed on THIS host.
#
# `mainCRTStartup` (self_host/codegen.ax, `emitWinEntry`) reads the
# process's command line and environment as UTF-16 from kernel32 and
# lays them out as the POSIX vector `Sys.ax` already reads -
# argv[0..argc-1], NULL, envp[0..m-1], NULL - narrowed to UTF-8. The
# split follows the rules `CommandLineToArgvW` documents, and a wrong
# rule produces a PLAUSIBLE argv rather than a crash: a path with a
# space split in two, a trailing backslash eaten, a `""` dropped. No
# runner in this repository executes a Windows binary, so those rules
# would otherwise be checked by nothing until someone typed a path with
# a space on a machine this tree has never seen.
#
# But the parsing is not Windows-specific - it is loads and stores over
# memory, in functions that call nothing but each other. So this gate
# emits a Windows module, cuts the `@__axiom_win_*` helpers out of it,
# assembles them for THE HOST under the host's own triple, links them
# to a C harness (libc is fine in a harness; it is not Axiom's output),
# and runs them against command lines and environment blocks with
# known answers. What executes is the bytes the emitter wrote for
# Windows, on the machine at hand.
#
# WHAT THIS DOES NOT SHOW: that `GetCommandLineW` is called, that the
# vector reaches `@__axiom_argc`/`@__axiom_argv`, that `ExitProcess`
# ends the process. Those are the entry's calls into kernel32 and only
# a Windows runner sees them. The CI leg for that is a later phase, and
# until it exists the README's Targets section says so.
#
# NEGATIVE PROBES. Two rules are ablated in the extracted IR and the
# harness must disagree with the golden on exactly the cases that spend
# them - a gate that cannot go red on a wrong rule would be asserting
# that the harness ran, not that the parser is right.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

status=0

# The module the helpers are cut from. Any program with an entry
# carries them; the hello case is the smallest.
if ! "$axc" --target=windows-x86_64 emit-llvm tests/stdlib/010-hello.ax -o "$work/win.ll" >"$work/emit.log" 2>&1; then
  echo "FAIL: could not emit tests/stdlib/010-hello.ax for windows-x86_64"
  sed 's/^/    /' "$work/emit.log" | head -5
  exit 1
fi

# Cut every `define internal i64 @__axiom_win_...` through its closing
# brace, drop `internal` so the harness can name them, keep the module's
# own `attributes #0` - the functions carry `#0`, and `no-builtins` is
# what stops the host's optimiser turning the narrowing loop into a
# libc call - and give the whole thing the host's triple.
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
extract_shim "$work/win.ll" > "$work/shim.ll"
nfun="$(grep -c '^define i64 @__axiom_win_' "$work/shim.ll" || true)"
if [[ "$nfun" -ne 6 ]]; then
  echo "FAIL: cut $nfun \`__axiom_win_*\` helpers out of the Windows module; the entry shim emits 6"
  echo "     (wlen, put, narrow, args, blocklen, env) - the emitter moved and this gate stopped reading it"
  exit 1
fi

# The harness. `u""` literals are UTF-16 on every host this runs on
# (clang and gcc agree); `char16_t` is spelled out because macOS ships
# no <uchar.h>. Each case prints `argc=N` then one `[arg]` line per
# argument; an environment block prints `envc=N units=U` then its
# entries.
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

# The golden. Every line is what the rules above produce for the case
# beside it in the harness; the two non-ASCII lines are the UTF-8 of
# U+00E9, U+1D11E and U+FFFD, written as bytes so the file is bytes.
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
if run_harness "$work/shim.ll" real && cmp -s "$work/real.out" "$work/expected"; then
  echo "ok   the entry shim's parsers answer all $cases cases on $host_triple, at -O1 and -O2"
else
  echo "FAIL the entry shim's parsers do not answer the golden"
  { diff "$work/expected" "$work/real.out" 2>/dev/null || true; } | head -20 | sed 's/^/    /'
  for f in real.llc.err real.cc.err; do [[ -s "$work/$f" ]] && head -5 "$work/$f" | sed 's/^/    /'; done
  status=1
fi

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
