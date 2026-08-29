#!/usr/bin/env bash
# Assert that Axiom's generated code needs no C library.
#
# This is the property that distinguishes an Axiom-native standard
# library from a set of thin wrappers around libc, and it is invisible in
# program output: a `printf`-backed `println` prints exactly the same
# bytes. So it gets its own check, at two levels:
#
#   1. the generated LLVM IR contains no call to a libc function, and
#   2. the linked executable imports no libc symbol.
#
# (2) is the stronger claim but is checked leniently on macOS, where the
# system linker always records a dependency on `libSystem` for the C
# runtime startup stub even when nothing in the program calls into it;
# there, the check is that no *libc function* is imported, not that no
# library is linked.
#
# WINDOWS IS THE SAME RELAXATION ONE NOTCH FURTHER, AND STRICTER FOR IT.
# A windows-x86_64 program imports kernel32 - there is no syscall ABI,
# so `VirtualAlloc` stands where `mmap` does and `WriteFile` where
# `write` does - and the claim becomes "no libc function is imported,
# and every non-libc import is on a reviewed list":
# `scripts/platform-allow.windows.txt`, one name per line, checked in,
# so a runtime that starts needing one more kernel32 entry point
# changes a reviewed file rather than silently widening the boundary
# (the mechanism is `check-ffi.sh`'s manifest, verbatim). Linux and
# macOS assert a NEGATIVE - no name from the sixty below; Windows
# asserts a POSITIVE - nothing outside the list. The list may not
# launder a libc name, and it is allowed to shrink and not to grow
# silently. Today the Windows half reads the IR's `declare`s - the
# import surface before anything links - and the PE reader below is
# what the executable half will use when a Windows executable exists.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

# Names that only ever belong to C. Axiom's own standard library defines
# `exit`, `write`, and `read`, which compile to calls on Axiom functions
# of those names, so listing them here would flag the replacement code
# itself.
#
# The process-control family joined the list when `Sys` learned to spawn
# children. That capability is the one place where reaching for libc is
# genuinely tempting - `posix_spawn` is a function, not a syscall, on
# every system that documents it - and until these names were listed the
# gate could not tell the raw-syscall implementation from the forbidden
# one: a `(foreign posix_spawn ...)` binding emitted `call i64
# @posix_spawn(...)`, linked against libc, and passed both the IR grep
# and the `nm` check. Verified before adding them.
#
# `foreign` has since been removed from the language, so nothing can
# emit such a call any more. The list stays: it is what would notice a
# BACKEND that started lowering something to a libc name, which is a
# different door from the source-level one, and the last probe below is
# what keeps the source-level one shut.
libc_names='printf|puts|malloc|calloc|realloc|free|strlen|strcmp|fopen|fwrite|fread'
libc_names="$libc_names"'|fork|vfork|execv|execve|execvp|execl|execlp|posix_spawn|posix_spawnp'
libc_names="$libc_names"'|wait|waitpid|wait3|wait4|system|popen|pclose|getenv|setenv|pipe|dup2'
# The mem/str family. The stage1 paragraph below records the measured
# bug as "linked against `_strlen` and `_memset`" - and `memset` was
# never on this list, so of the two symbols that motivated the stage1
# pass only ONE could ever have been caught. Found 2026-08-16: an
# executable importing `_memset` or `_bzero` got a green `ok`.
#
# These are the names the loop-idiom recogniser reaches for, which is
# the exact door the stage1 pass exists to watch: it rewrites a byte
# loop into `strlen`, a zeroing loop into `memset`, and a copy loop
# into `memcpy`. None of them is defined by Axiom's stdlib, so unlike
# `exit`/`write`/`read` there is no replacement code to flag.
libc_names="$libc_names"'|memset|memcpy|memmove|memcmp|memchr|bzero|bcopy'
libc_names="$libc_names"'|strcpy|strncpy|strcat|strncat|strncmp|strchr|strrchr|strstr|strdup'
# The socket family, added 2026-08-24 when `Sys` learned to open one -
# the same reason and the same moment the process-control family above
# was added when it learned to spawn. A capability that reaches the
# network is the other place where reaching for libc is tempting, and
# `getaddrinfo` is the specific temptation: it is the only way to
# resolve a NAME, it lives in libc, and it is why `Sys.ax`'s socket
# section says numeric addresses only.
#
# None of these can be tripped by the code as written - a `__syscallN`
# emits inline asm, not a call to a named symbol - so this list is not
# guarding today's implementation. It guards the next one: a backend
# that started lowering something to `@socket`, or a contributor who
# reached for the easy answer, is invisible to every other gate.
#
# The `sysXxx`/`netXxx` prefix convention is load-bearing here. The IR
# pattern is anchored by `@` and `(` but is NOT word-anchored inside, so
# an Axiom function named plainly `bind`, `send`, `accept`, `connect` or
# `poll` would emit `@bind(` and be flagged by its own name. `netBind`
# and `netAccept` cannot be.
libc_names="$libc_names"'|socket|socketpair|bind|listen|accept|accept4|connect|shutdown'
libc_names="$libc_names"'|setsockopt|getsockopt|getaddrinfo|freeaddrinfo|gethostbyname'
libc_names="$libc_names"'|kqueue|kevent|epoll_create|epoll_create1|epoll_ctl|epoll_wait|select'
# Entropy, added when `Sys` learned to ask the kernel for random bytes.
# `arc4random` is the specific temptation here the way `getaddrinfo` is
# for sockets: it is the convenient spelling, it lives in libc, and
# reaching for it would cost the freestanding property while looking
# like an improvement. `sysRandomBytes` goes to the syscall.
libc_names="$libc_names"'|getentropy|getrandom|arc4random|arc4random_buf|rand|srand|random'
# Signals, added when `Sys` learned to hear one. `signal` and
# `sigaction` are the temptation here and they are worse than the
# others: reaching for them does not merely link libc, it needs a
# callback with the shape `void(int, siginfo_t*, void*)`, which no Axiom
# function can have. A gate that catches the attempt is cheaper than
# discovering that at the ABI.
libc_names="$libc_names"'|signal|sigaction|sigprocmask|pthread_sigmask|sigemptyset|sigaddset'
libc_names="$libc_names"'|kill|raise|signalfd|sigwait|sigwaitinfo|sigsuspend|alarm'

# The undefined symbols an executable imports, as bare names, on any
# of the three object formats. ONE COPY, because the negative probes
# below run the same function the sweep does - a probe against a second
# copy of a pipeline proves the copy works and nothing else.
#
# `sed 's/@.*//'` IS THE ELF HALF OF THE COMPARISON, and without it this
# check could not fail on Linux. GNU `nm -D --undefined-only` prints a
# versioned import as `malloc@GLIBC_2.2.5`, and the test below is
# anchored - `grep -qE "^($libc_names)$"` - so `malloc` never matched
# `malloc@GLIBC_2.2.5` and a program that really did import libc
# passed. Mach-O has no version suffix and needs its leading underscore
# stripped instead; each platform gets the one edit its own convention
# requires, which is the lesson `check-backtrace.sh` records after
# applying Mach-O's to ELF.
#
# THE READER MOVED to `scripts/lib/imports.sh` on 2026-08-29, when a
# third format arrived and a second script needed to read it: it
# dispatches on the object's own magic - MZ, ELF, Mach-O - rather than
# on the host, and the Windows hello gate reads a `.exe` through the
# same function. `permitted_windows`, `unpermitted_imports` and
# `declares_of` live beside it for the same reason.
source "$(dirname "${BASH_SOURCE[0]}")/lib/imports.sh"

# The Windows import allowlist.
win_allow="scripts/platform-allow.windows.txt"
# The names an allowlist would launder: anything on it that is a libc
# name is refused whatever the list says, exactly as check-ffi.sh's
# `never_permitted` refuses a manifest.
manifest_launders() {
  permitted_windows "$1" | grep -E "^($libc_names)$" || true
}

status=0

for case_file in tests/stdlib/*.ax; do
  name="$(basename "$case_file" .ax)"

  ir="$work/$name.ll"
  "$axc" emit-llvm "$case_file" -o "$ir" > /dev/null

  if grep -nE "call[^\"]*@($libc_names)\(" "$ir" > "$work/$name.hits"; then
    echo "FAIL $name: generated IR calls libc"
    sed 's/^/    /' "$work/$name.hits"
    status=1
    continue
  fi

  # The INTRINSIC spelling of the same thing, which the pattern above
  # structurally cannot match: `@llvm.memset.p0.i64` does not begin
  # with `memset` after the `@`, so adding the name to `libc_names`
  # would not have found it either. An `llvm.mem*` intrinsic is not a
  # libc call in the IR, but the backend lowers anything it cannot
  # expand inline into one - so a program can arrive at `memcpy` with
  # no libc name appearing in the IR at any point.
  if grep -nE "@llvm\.(memset|memcpy|memmove)\." "$ir" > "$work/$name.intr"; then
    echo "FAIL $name: generated IR uses an llvm.mem* intrinsic, which lowers to libc"
    sed 's/^/    /' "$work/$name.intr"
    status=1
    continue
  fi

  exe="$work/$name.bin"
  "$axc" build --input "$case_file" --output "$exe" > /dev/null

  imports="$(imports_of "$exe")"

  if printf '%s\n' "$imports" | grep -qE "^($libc_names)$"; then
    echo "FAIL $name: executable imports libc symbols"
    printf '%s\n' "$imports" | grep -E "^($libc_names)$" | sed 's/^/    /'
    status=1
    continue
  fi

  echo "ok   $name (no libc in IR or imports)"
done

# ---------------------------------------------------------------
# The Windows half: every case, emitted for windows-x86_64, calls no
# libc function and declares nothing outside the allowlist.
#
# The list is read first and held to two rules before a single case is
# compared against it: it must permit at least the four names the
# emitted runtime cannot do without (a list that parsed to nothing would
# pass every `comm` below vacuously), and it may not carry a libc name.
# ---------------------------------------------------------------
echo "--- windows-x86_64: every declare is on $win_allow ---"
if [[ ! -f "$win_allow" ]]; then
  echo "FAIL $win_allow is missing; the Windows import surface is enumerated there"
  status=1
else
  n_permitted_win="$(permitted_windows "$win_allow" | grep -c . || true)"
  laundered="$(manifest_launders "$win_allow")"
  if (( n_permitted_win < 4 )); then
    echo "FAIL $win_allow permits only $n_permitted_win name(s); the runtime alone needs VirtualAlloc, GetStdHandle, WriteFile and ExitProcess"
    status=1
  elif [[ -n "$laundered" ]]; then
    echo "FAIL $win_allow permits libc name(s), which no list may:"
    printf '%s\n' "$laundered" | sed 's/^/    /'
    status=1
  else
    for case_file in tests/stdlib/*.ax; do
      name="$(basename "$case_file" .ax)"
      wir="$work/$name.win.ll"
      if ! "$axc" --target=windows-x86_64 emit-llvm "$case_file" -o "$wir" > "$work/$name.win.emit" 2>&1; then
        echo "FAIL $name [windows-x86_64]: emit-llvm"
        sed 's/^/    /' "$work/$name.win.emit" | head -5
        status=1
        continue
      fi
      if grep -nE "call[^\"]*@($libc_names)\(" "$wir" > "$work/$name.win.hits"; then
        echo "FAIL $name [windows-x86_64]: generated IR calls libc"
        sed 's/^/    /' "$work/$name.win.hits"
        status=1
        continue
      fi
      if grep -nE "@llvm\.(memset|memcpy|memmove)\." "$wir" > "$work/$name.win.intr"; then
        echo "FAIL $name [windows-x86_64]: generated IR uses an llvm.mem* intrinsic, which lowers to libc"
        sed 's/^/    /' "$work/$name.win.intr"
        status=1
        continue
      fi
      declares_of "$wir" > "$work/$name.win.declares"
      n_decl="$(grep -c . "$work/$name.win.declares" || true)"
      if (( n_decl < 4 )); then
        echo "FAIL $name [windows-x86_64]: the reader found $n_decl declare(s); the runtime alone writes four, so the emitter moved and this check stopped reading it"
        status=1
        continue
      fi
      unexpected="$(unpermitted_imports "$work/$name.win.declares" "$win_allow")"
      if [[ -n "$unexpected" ]]; then
        echo "FAIL $name [windows-x86_64]: the IR declares symbols $win_allow does not permit:"
        printf '%s\n' "$unexpected" | sed 's/^/    /'
        echo "    (a kernel32 entry point the runtime or Sys/Platform.windows.ax now needs is added to the list, in a reviewed diff)"
        status=1
        continue
      fi
      echo "ok   $name [windows-x86_64] (no libc in IR; $n_decl declares, all of $n_permitted_win permitted)"
    done
  fi
fi

# WHICH COMPILER ANSWERS FOR THIS, and why there used to be two passes.
#
# This gate ran the corpus twice: once through `$axiom` and once through
# a `stage1` it built from `self_host/`. The second pass was added for a
# real bug living in the gap - `opt` rewrites a byte loop into a call to
# `strlen` when it can, and it can on stage1's register/phi IR while it
# could not on stage0's alloca form. Every case failed and the gate was
# green, because it only ever asked stage0.
#
# That argument was written when `$axiom` meant stage0, the RUST
# compiler: a genuinely different backend, whose disagreement with the
# self-hosted one was worth a second pass. It means something else now.
# `$axiom` is what `bootstrap-from-seed.sh` builds from the COMMITTED
# SEED - the same backend, from whenever the seed was last cut - so
# "both compilers" had become "this one, and a snapshot of it". The
# stage1 pass was not testing a second backend; it was testing the only
# one, and the first pass was testing an old copy.
#
# It also had a hard consequence rather than a philosophical one: a
# fixture exercising anything the seed does not know cannot be compiled
# by it at all, whatever the compiler in the tree thinks. The three
# recovery-point cases arrived and this gate refused them with
# `undefined variable __axiom_recover` against a tree where they build,
# run, and answer their goldens.
#
# So there is one pass and it uses `gate_build_axc`'s artifact - the
# compiler this tree builds, through its own driver, which is what the
# stage1 pass was for. The freestanding contract still belongs to the
# language rather than to one backend; what changed is that there is
# only one backend left to ask.

# ---------------------------------------------------------------
# Negative probes: the IR check can still fail, and the language has
# no way to ask for a libc call in the first place.
#
# A gate that has never been seen to fail is a gate nobody has checked.
# Everything above asserts SILENCE - no libc in any case - and silence
# is exactly what a broken grep, an empty corpus, or a mistyped
# alternation also produces.
#
# This used to be one probe, an Axiom program built on
# `(foreign posix_spawn ...)`, and it worked because `foreign` emitted
# `call i64 @posix_spawn(...)` verbatim. `foreign` has been removed -
# it named a symbol the emitted module never declared, so every
# program that used one passed `check` and then died in `opt` - and
# with it went the only construct that could name an external symbol
# at all. A probe cannot be written in Axiom any more.
#
# That is a strictly better world and a strictly worse test, so the
# two halves it used to prove at once are now proved separately.
# ---------------------------------------------------------------

# 1. The forbidden-name list catches what it claims to, checked against
#    IR lines this script writes itself - one per name in the list, not
#    just the one a probe happened to call. The old probe exercised
#    exactly one alternative of the alternation, so a typo in any of the
#    other thirty was invisible.
missed=""
IFS='|' read -r -a forbidden <<< "$libc_names"
for fname in "${forbidden[@]}"; do
  grep -qE "call[^\"]*@($libc_names)\(" <<< "  %r = call i64 @$fname(i64 0)" \
    || missed="$missed $fname"
done
if (( ${#forbidden[@]} < 25 )); then
  echo "FAIL negative probe: the forbidden-name list parsed to only ${#forbidden[@]} names"
  status=1
elif [[ -n "$missed" ]]; then
  echo "FAIL negative probe: the IR check does not catch a call to$missed"
  status=1
else
  echo "ok   negative probe: the IR check catches a call to each of ${#forbidden[@]} libc names"
fi

# And it DISCRIMINATES. A pattern that matched every line would pass the
# loop above while reporting the whole standard library as libc, so the
# grep is also shown refusing a call the corpus makes on every run -
# `@axiom_alloc` is Axiom's own, and the substring hazard is real:
# `free` sits inside a name like `freelist` and `wait` inside `awaited`,
# so this is what would notice the alternation losing its anchors.
# The `net*` names below are the socket family's half of the same
# hazard, and they are here because the prefix convention is what makes
# them safe rather than luck: `bind`, `accept`, `connect` and `socket`
# all went onto the list above, and `@netBind(` must not match `@bind(`.
# If someone ever drops the prefix, this probe is what says so.
kept=""
for ok_name in axiom_alloc freelist awaited printfmt __syscall1 \
               netBind netAccept netConnect netSocketTcp netListen \
               netPollCreate netPollWait sysRandomBytes randomMaxChunk \
               sysKill sysSignalBlock netSignalOpen signalUsesSignalFd \
               sysForkProcess forkChildIsZero netSetBlocking; do
  grep -qE "call[^\"]*@($libc_names)\(" <<< "  %r = call i64 @$ok_name(i64 0)" \
    && kept="$kept $ok_name"
done
if [[ -n "$kept" ]]; then
  echo "FAIL negative probe: the IR check flags non-libc name(s)$kept"
  status=1
else
  echo "ok   negative probe: the IR check leaves Axiom's own call names alone"
fi

# The OTHER direction, which nothing here asserted: that the patterns
# above actually FIRE. A gate is only worth its green when it has been
# shown to go red, and this one had been silently half-blind - the
# stage1 paragraph below names `_memset` as a symbol it caught, while
# `memset` was absent from `libc_names` until 2026-08-16, so that half
# of the claim had never been true. Each line here is a shape the
# corpus cannot produce today; if the recogniser ever emits one, the
# check that notices is the one being probed.
missed=""
for bad_line in \
  '  %r = call i64 @memset(i64 0, i64 0, i64 8)' \
  '  %r = call i64 @memcpy(i64 0, i64 0, i64 8)' \
  '  %r = call i64 @strlen(i64 0)' \
  '  %r = call i64 @malloc(i64 8)' \
  '  %r = call i64 @posix_spawn(i64 0)' \
  '  %r = call i64 @socket(i64 2, i64 1, i64 0)' \
  '  %r = call i64 @bind(i64 3, i64 0, i64 16)' \
  '  %r = call i64 @accept(i64 3, i64 0, i64 0)' \
  '  %r = call i64 @getaddrinfo(i64 0, i64 0, i64 0, i64 0)' \
  '  %r = call i64 @epoll_wait(i64 4, i64 0, i64 8, i64 0)' \
  '  %r = call i64 @kevent(i64 4, i64 0, i64 1, i64 0, i64 1, i64 0)' \
  '  %r = call i64 @getentropy(i64 0, i64 32)' \
  '  %r = call i64 @getrandom(i64 0, i64 32, i64 0)' \
  '  %r = call i64 @arc4random_buf(i64 0, i64 32)' \
  '  %r = call i64 @sigaction(i64 15, i64 0, i64 0)' \
  '  %r = call i64 @kill(i64 1, i64 15)' \
  '  %r = call i64 @signalfd(i64 -1, i64 0, i64 0)' ; do
  grep -qE "call[^\"]*@($libc_names)\(" <<< "$bad_line" \
    || missed="$missed ${bad_line##*@}"
done
for intr_line in \
  '  call void @llvm.memset.p0.i64(ptr %d, i8 0, i64 8, i1 false)' \
  '  call void @llvm.memcpy.p0.p0.i64(ptr %d, ptr %s, i64 8, i1 false)' ; do
  grep -qE "@llvm\.(memset|memcpy|memmove)\." <<< "$intr_line" \
    || missed="$missed ${intr_line##*@}"
done
if [[ -n "$missed" ]]; then
  echo "FAIL negative probe: the IR checks do NOT flag$missed"
  status=1
else
  echo "ok   negative probe: the IR checks flag libc calls and llvm.mem* intrinsics"
fi

# 2. The door is shut in the language, not merely unused by the corpus.
#    A sweep over programs that do not call libc says nothing about
#    whether one COULD; this is the check that says it cannot, and it is
#    the reason (1) no longer has an Axiom program behind it.
ffi="$work/ffi-probe.ax"
cat > "$ffi" <<'PROBE'
(foreign posix_spawn :: (-> Int Int Int Int Int Int) = "posix_spawn")
(pub :: main Int)
(pub fn (main) (posix_spawn 0 0 0 0 0))
PROBE
# Assigned inside the `if` condition, not before it: this script runs
# under `set -e`, and a bare `out="$(cmd)"` whose command exits non-zero
# takes the whole script down. Here a non-zero exit is the PASSING
# outcome, so writing it that way killed the gate one line before its
# own result - exit 1, no verdict printed, which reads as a failure
# somewhere else entirely.
if ffi_out="$("$axiom" --diagnostic-format=ai check "$ffi" 2>&1)"; then
  echo "FAIL negative probe: a \`foreign\` binding still compiles - the FFI is back"
  status=1
elif ! grep -q 'AX2004' <<< "$ffi_out"; then
  echo "FAIL negative probe: \`foreign\` is refused, but not as a removed construct"
  printf '%s\n' "$ffi_out" | sed 's/^/    /' | head -3
  status=1
else
  echo "ok   negative probe: \`foreign\` is refused as a removed construct (AX2004)"
fi

# ------------------------------------------------------------------
# THE NEGATIVE PROBE THE IMPORTS CHECK NEVER HAD.
#
# This file's header calls the executable-imports check "the stronger
# claim" of its two, and until 2026-08-25 every negative probe above
# tested the OTHER one - the IR grep. The stronger claim had never been
# observed red on either platform, which is this repository's most
# common defect shape sitting in the check that exists to catch a libc
# dependency the IR does not name.
#
# It is deliberately not an Axiom program. Axiom cannot easily be made
# to import libc without an `extern` and an archive, which is
# `check-ffi.sh`'s subject and needs cargo; what wants proving here is
# that the INSTRUMENT can see a violation, not that the language can
# commit one. A three-line C file linked by the same `cc` the driver
# shells out to imports `malloc` and `memset` on every platform this
# repository builds for, and it goes through `imports_of` - the same
# function the sweep above uses, not a second copy of it.
#
# It is also what would have caught the ELF version suffix: on Linux
# this probe's `malloc` arrives from `nm -D` as `malloc@GLIBC_2.2.5`
# and, before `imports_of` learned to strip it, matched nothing.
# ------------------------------------------------------------------
printf '#include <stdlib.h>\n#include <string.h>\nint main(void) { void *p = malloc(16); memset(p, 0, 16); return p != 0; }\n' \
  > "$work/libcuser.c"
if ! cc -o "$work/libcuser" "$work/libcuser.c" >"$work/libcuser.log" 2>&1; then
  echo "FAIL negative probe: could not build the C program that imports libc"
  sed 's/^/    /' "$work/libcuser.log" | head -5
  status=1
else
  probe_imports="$(imports_of "$work/libcuser")"
  probe_hits="$(printf '%s\n' "$probe_imports" | grep -E "^($libc_names)$" | sort -u | tr '\n' ' ')"
  if [[ -z "$probe_hits" ]]; then
    echo "FAIL negative probe: the imports check does NOT catch a program that imports libc"
    echo "     it read $(printf '%s\n' "$probe_imports" | grep -c . || true) undefined symbol(s) and matched none of them:"
    printf '%s\n' "$probe_imports" | head -8 | sed 's/^/        /'
    status=1
  else
    echo "ok   negative probe: the imports check catches a C program importing ${probe_hits% }"
  fi
fi

# ------------------------------------------------------------------
# THE WINDOWS HALF'S NEGATIVE PROBES, four of them, matching the count
# above. Everything in the Windows clause asserts silence - no libc, no
# unpermitted name - and a PE arm that answered nothing, an allowlist
# that matched everything, or a manifest check that never ran would
# all be silent too.
#
# 1. THE PE READER SEES IMPORTS AT ALL. A real PE that imports
#    `MessageBoxA` from user32 is linked here - `llc` under the Windows
#    triple, `lld-link` against an import library `llvm-dlltool`
#    generates from a four-line `.def`, no Windows SDK anywhere - and
#    `imports_of` must answer that name. This is the ELF `@GLIBC` trap
#    over again: a reader that silently reads zero imports passes the
#    allowlist vacuously. Written in IR rather than C because the
#    Windows path has no C compiler in it, by decision, and llc and
#    lld-link are the whole toolchain.
# 2. THE ALLOWLIST REFUSES. `HeapAlloc` - a plausible wrong answer to
#    "how does the runtime get memory" - fed to the same comparison the
#    sweep uses must come back unpermitted.
# 3. THE ALLOWLIST DISCRIMINATES. `VirtualAlloc`, in the same list, must
#    not.
# 4. THE LAUNDER RULE WINS. A copy of the real list with `malloc`
#    appended must be refused by the same function the sweep runs.
# ------------------------------------------------------------------
for tool in lld-link llvm-dlltool llvm-readobj; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "FAIL negative probe: $tool is not on PATH; it ships with LLVM (lld-link with lld) and the PE probe links with it"
    status=1
  fi
done
if command -v lld-link > /dev/null 2>&1 && command -v llvm-dlltool > /dev/null 2>&1; then
  pew="$work/pe-probe"
  mkdir -p "$pew"
  cat > "$pew/probe.ll" <<'IR'
target triple = "x86_64-pc-windows-msvc"

declare dllimport i32 @MessageBoxA(ptr, ptr, ptr, i32)

define i32 @mainCRTStartup() {
entry:
  %r = call i32 @MessageBoxA(ptr null, ptr null, ptr null, i32 0)
  ret i32 0
}
IR
  printf 'LIBRARY user32.dll\nEXPORTS\nMessageBoxA\n' > "$pew/user32.def"
  if ! llc -filetype=obj -relocation-model=pic "$pew/probe.ll" -o "$pew/probe.o" >"$pew/log" 2>&1 \
     || ! llvm-dlltool -m i386:x86-64 -d "$pew/user32.def" -l "$pew/user32.lib" >>"$pew/log" 2>&1 \
     || ! lld-link /subsystem:console /entry:mainCRTStartup "/out:$pew/probe.exe" "$pew/probe.o" "$pew/user32.lib" >>"$pew/log" 2>&1; then
    echo "FAIL negative probe: could not link the PE that imports MessageBoxA"
    sed 's/^/    /' "$pew/log" | head -5
    status=1
  else
    pe_imports="$(imports_of "$pew/probe.exe" || true)"
    if ! grep -qx 'MessageBoxA' <<< "$pe_imports"; then
      echo "FAIL negative probe: the PE reader does NOT see a Windows executable's imports"
      echo "     it read $(printf '%s\n' "$pe_imports" | grep -c . || true) name(s) from probe.exe and MessageBoxA was not one of them"
      status=1
    else
      echo "ok   negative probe: the PE reader sees MessageBoxA imported by a linked Windows executable"
    fi
    # And the same executable against the real allowlist: MessageBoxA is
    # not on it and must come back as the one unpermitted name.
    printf '%s\n' "$pe_imports" > "$pew/imports"
    if [[ "$(unpermitted_imports "$pew/imports" "$win_allow" | tr '\n' ' ')" == "MessageBoxA " ]]; then
      echo "ok   negative probe: a linked executable importing MessageBoxA is refused by $win_allow"
    else
      echo "FAIL negative probe: MessageBoxA in a real PE was not the one unpermitted import: '$(unpermitted_imports "$pew/imports" "$win_allow" | tr '\n' ' ')'"
      status=1
    fi
  fi
fi

printf 'VirtualAlloc\nHeapAlloc\n' > "$work/synthetic-imports"
got="$(unpermitted_imports "$work/synthetic-imports" "$win_allow" | tr '\n' ' ')"
if [[ "$got" == "HeapAlloc " ]]; then
  echo "ok   negative probe: the allowlist refuses HeapAlloc and permits VirtualAlloc"
else
  echo "FAIL negative probe: expected HeapAlloc alone to be unpermitted, got '$got'"
  status=1
fi

{ cat "$win_allow"; printf 'malloc\n'; } > "$work/laundering-allow.txt"
if [[ "$(manifest_launders "$work/laundering-allow.txt" | tr '\n' ' ')" == "malloc " ]]; then
  echo "ok   negative probe: an allowlist carrying malloc is refused whatever it says"
else
  echo "FAIL negative probe: an allowlist carrying malloc was not refused"
  status=1
fi
if [[ -n "$(manifest_launders "$win_allow")" ]]; then
  echo "FAIL negative probe: the real allowlist launders a libc name, so the probe above proves nothing"
  status=1
fi

exit "$status"
