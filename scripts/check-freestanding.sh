#!/usr/bin/env bash
# Assert that Axiom's generated code needs no C library.
#
# Program output cannot show this: a `printf`-backed `println` prints
# the same bytes. So the gate checks two levels:
#
#   1. the generated LLVM IR contains no call to a libc function, and
#   2. the linked executable imports no libc symbol.
#
# (2) is the stronger claim. On macOS the linker always records a
# dependency on `libSystem` for the C startup stub, so there the check
# is only that no libc *function* is imported.
#
# Windows has no syscall ABI, so a program imports kernel32:
# `VirtualAlloc` stands in for `mmap` and `WriteFile` for `write`. There,
# no libc function may be imported, and every other import must be on
# `scripts/platform-allow.windows.txt`, a reviewed list in the form of
# `check-ffi.sh`'s manifest. Linux and macOS assert that no listed libc
# name appears; Windows asserts that nothing outside the list does. The
# list may not carry a libc name, and it grows only in a reviewed diff.
# The Windows half here reads the IR's `declare`s. A linked `.exe`'s
# imports are read by `check-windows-hello.sh`, through the same PE
# reader in `scripts/lib/imports.sh` that the probes below exercise.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

# Names that only ever belong to C. Axiom's own standard library defines
# `exit`, `write` and `read`, so listing them would flag the replacement
# code itself.
#
# The process-control family guards `Sys`'s spawning code. `posix_spawn`
# is a libc function, not a syscall, so it is the tempting shortcut.
# The list also catches a backend that starts lowering to a libc name.
# In source, `foreign` is refused (probed below) and an `extern` block
# is `check-ffi.sh`'s subject.
libc_names='printf|puts|malloc|calloc|realloc|free|strlen|strcmp|fopen|fwrite|fread'
libc_names="$libc_names"'|fork|vfork|execv|execve|execvp|execl|execlp|posix_spawn|posix_spawnp'
libc_names="$libc_names"'|wait|waitpid|wait3|wait4|system|popen|pclose|getenv|setenv|pipe|dup2'
# The mem/str family. These are the names LLVM's loop-idiom recogniser
# reaches for: `opt` rewrites a byte loop into `strlen`, a zeroing loop
# into `memset` and a copy loop into `memcpy`. Axiom's stdlib defines
# none of them, so nothing legitimate is flagged.
libc_names="$libc_names"'|memset|memcpy|memmove|memcmp|memchr|bzero|bcopy'
libc_names="$libc_names"'|strcpy|strncpy|strcat|strncat|strncmp|strchr|strrchr|strstr|strdup'
# The socket family. `getaddrinfo` is the tempting shortcut: it is the
# only way to resolve a name, and it lives in libc, which is why
# `Sys.ax`'s socket section takes numeric addresses only. A `__syscallN`
# emits inline asm, not a named call, so these names guard against a
# future backend or shortcut rather than today's code.
#
# The `sysXxx`/`netXxx` prefixes matter here. The IR pattern is anchored
# by `@` and `(` but not word-anchored inside, so an Axiom function named
# plainly `bind`, `send`, `accept`, `connect` or `poll` would be flagged
# by its own name. `netBind` and `netAccept` cannot be.
libc_names="$libc_names"'|socket|socketpair|bind|listen|accept|accept4|connect|shutdown'
libc_names="$libc_names"'|setsockopt|getsockopt|getaddrinfo|freeaddrinfo|gethostbyname'
libc_names="$libc_names"'|kqueue|kevent|epoll_create|epoll_create1|epoll_ctl|epoll_wait|select'
# Entropy. `arc4random` is the convenient libc spelling, and
# `sysRandomBytes` goes to the syscall instead.
libc_names="$libc_names"'|getentropy|getrandom|arc4random|arc4random_buf|rand|srand|random'
# Signals. `signal` and `sigaction` would also need a callback of type
# `void(int, siginfo_t*, void*)`, which no Axiom function can have.
libc_names="$libc_names"'|signal|sigaction|sigprocmask|pthread_sigmask|sigemptyset|sigaddset'
libc_names="$libc_names"'|kill|raise|signalfd|sigwait|sigwaitinfo|sigsuspend|alarm'

# `imports_of` lists the undefined symbols an executable imports, as
# bare names, for ELF, Mach-O and PE. It lives in `scripts/lib/imports.sh`
# with `permitted_windows`, `unpermitted_imports` and `declares_of`, so
# the sweep and the negative probes below run one copy.
#
# It strips ELF's `@GLIBC_2.2.5` version suffix and Mach-O's leading
# underscore. Without the ELF edit, the anchored `^($libc_names)$` match
# could never fire on Linux.
source "$(dirname "${BASH_SOURCE[0]}")/lib/imports.sh"

# The Windows import allowlist.
win_allow="scripts/platform-allow.windows.txt"
# The names an allowlist would launder: a libc name on it is refused
# whatever the list says, as check-ffi.sh's `never_permitted` refuses a
# manifest.
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

  # The intrinsic spelling, which the pattern above cannot match:
  # `@llvm.memset.p0.i64` does not start with `memset` after the `@`.
  # The backend lowers any `llvm.mem*` it cannot expand inline into a
  # libc call, so a program can reach `memcpy` with no libc name in the IR.
  if grep -nE "@llvm\.(memset|memcpy|memmove)\." "$ir" > "$work/$name.intr"; then
    echo "FAIL $name: generated IR uses an llvm.mem* intrinsic, which lowers to libc"
    sed 's/^/    /' "$work/$name.intr"
    status=1
    continue
  fi

  exe="$work/$name.bin"
  "$axc" build --input "$case_file" --output "$exe" > /dev/null

  imports="$(imports_of "$exe")"

  if grep -qE "^($libc_names)$" <<< "$imports"; then
    echo "FAIL $name: executable imports libc symbols"
    printf '%s\n' "$imports" | grep -E "^($libc_names)$" | sed 's/^/    /'
    status=1
    continue
  fi

  echo "ok   $name (no libc in IR or imports)"
done

# ---------------------------------------------------------------
# The Windows half: every case, emitted for each Windows target
# (windows-x86_64 and windows-aarch64), calls no libc function and
# declares nothing outside the allowlist.
#
# The list is held to two rules before any case is compared with it. It
# must permit at least the four names the emitted runtime needs, since
# an empty parse would pass every comparison. And it may not carry a
# libc name.
# ---------------------------------------------------------------
echo "--- windows-x86_64, windows-aarch64: every declare is on $win_allow ---"
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
      for wt in windows-x86_64 windows-aarch64; do
        wir="$work/$name.$wt.ll"
        if ! "$axc" --target="$wt" emit-llvm "$case_file" -o "$wir" > "$work/$name.$wt.emit" 2>&1; then
          echo "FAIL $name [$wt]: emit-llvm"
          sed 's/^/    /' "$work/$name.$wt.emit" | head -5
          status=1
          continue
        fi
        if grep -nE "call[^\"]*@($libc_names)\(" "$wir" > "$work/$name.$wt.hits"; then
          echo "FAIL $name [$wt]: generated IR calls libc"
          sed 's/^/    /' "$work/$name.$wt.hits"
          status=1
          continue
        fi
        if grep -nE "@llvm\.(memset|memcpy|memmove)\." "$wir" > "$work/$name.$wt.intr"; then
          echo "FAIL $name [$wt]: generated IR uses an llvm.mem* intrinsic, which lowers to libc"
          sed 's/^/    /' "$work/$name.$wt.intr"
          status=1
          continue
        fi
        declares_of "$wir" > "$work/$name.$wt.declares"
        n_decl="$(grep -c . "$work/$name.$wt.declares" || true)"
        if (( n_decl < 4 )); then
          echo "FAIL $name [$wt]: the reader found $n_decl declare(s); the runtime alone writes four, so the emitter moved and this check stopped reading it"
          status=1
          continue
        fi
        unexpected="$(unpermitted_imports "$work/$name.$wt.declares" "$win_allow")"
        if [[ -n "$unexpected" ]]; then
          echo "FAIL $name [$wt]: the IR declares symbols $win_allow does not permit:"
          printf '%s\n' "$unexpected" | sed 's/^/    /'
          echo "    (a kernel32 entry point the runtime or Sys/Platform.windows.ax now needs is added to the list, in a reviewed diff)"
          status=1
          continue
        fi
        echo "ok   $name [$wt] (no libc in IR; $n_decl declares, all of $n_permitted_win permitted)"
      done
    done
  fi
fi

# The corpus runs once, through `gate_build_axc`'s compiler: the one this
# tree builds, through its own driver. `$axiom` is built from the
# committed seed, which shares the backend but cannot compile a fixture
# that uses a feature added after the seed was cut.

# ---------------------------------------------------------------
# Negative probes: the IR check can still fail, and the language
# refuses a `foreign` binding to a libc name.
#
# Everything above asserts silence, which a broken grep, an empty corpus
# or a mistyped alternation also produces. Outside an `extern` block no
# Axiom program can name an external symbol, so the pattern is probed
# with IR lines written here and the language with a `foreign` binding.
# ---------------------------------------------------------------

# 1. The forbidden-name list catches what it claims to. Each name gets
#    an IR line written here, so a typo in any alternative shows.
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

# And it discriminates. A pattern that matched every line would pass the
# loop above, so it must also leave Axiom's own call names alone. The
# hazard is substrings: `free` sits inside `freelist` and `wait` inside
# `awaited`, so this notices the alternation losing its anchors. The
# `net*` names check the prefix convention: `@netBind(` must not match
# `@bind(`.
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

# The other direction: the patterns fire on real call shapes, intrinsics
# included. The corpus cannot produce these lines today, so this is the
# only evidence the checks would notice the recogniser emitting one.
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

# 2. The language refuses `foreign`, which named a symbol with no
#    `extern` declaration behind it. A sweep over programs that do not
#    call libc cannot show that none could, so this checks that
#    `foreign` is refused as a removed construct.
ffi="$work/ffi-probe.ax"
cat > "$ffi" <<'PROBE'
(foreign posix_spawn :: (-> Int Int Int Int Int Int) = "posix_spawn")
(pub :: main Int)
(pub fn (main) (posix_spawn 0 0 0 0 0))
PROBE
# Assign inside the `if` condition. Under `set -e`, a bare
# `out="$(cmd)"` whose command fails kills the script with no verdict,
# and here a non-zero exit is the passing outcome.
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
# The imports check's negative probe.
#
# It shows the instrument can see a violation. A three-line C program,
# linked by the `cc` the driver uses, imports `malloc` and `memset` on
# every platform this repository builds for. It goes through
# `imports_of`, the sweep's own reader, and must be caught. An Axiom
# program would need an `extern` and an archive, which is
# `check-ffi.sh`'s subject and needs cargo.
#
# On Linux this probe's `malloc` arrives from `nm -D` as
# `malloc@GLIBC_2.2.5`, so it also checks the version-suffix stripping.
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
# The Windows half's negative probes. A PE reader that answered nothing,
# an allowlist that matched everything, or a launder check that never
# ran would all read as silence too.
#
# 1. The PE reader sees imports. A real PE importing `MessageBoxA` from
#    user32 is linked here: `llc` under the Windows triple, then
#    `lld-link` against an import library `llvm-dlltool` builds from a
#    `.def`, with no Windows SDK. `imports_of` must answer that name, or
#    the allowlist passes vacuously. It is written in IR because the
#    Windows path has no C compiler, only llc and lld-link.
# 2. The allowlist refuses `HeapAlloc`, a plausible wrong answer to "how
#    does the runtime get memory".
# 3. The allowlist discriminates: `VirtualAlloc`, in the same input,
#    stays permitted.
# 4. The launder rule wins: a copy of the real list with `malloc`
#    appended is refused by the same function the sweep runs.
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
     || ! lld-link -subsystem:console -entry:mainCRTStartup "-out:$pew/probe.exe" "$pew/probe.o" "$pew/user32.lib" >>"$pew/log" 2>&1; then
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
