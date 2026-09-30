#!/usr/bin/env bash
# A hello world for both Windows targets, windows-x86_64 and
# windows-aarch64: emitted on any host, linked and EXECUTED on a Windows
# runner, its output compared byte for byte with the golden, and its
# imports held to `scripts/platform-allow.windows.txt`.
#
# This is the gate that decides whether a Windows target is on its way
# to being supported at all - README's Targets section defines supported
# as "a CI leg executes what the compiler emits there", and this is the
# executing. It runs in two halves, on two machines, because the two
# halves need two toolchains:
#
#   --emit DIR     on a host with the tree's compiler: emit the hello
#                  case and the leaky probe for each Windows target into
#                  DIR/<target>/, beside the golden they must answer. The
#                  `cross` CI job runs this half.
#
#   --run DIR [TARGET]
#                  on a Windows runner with LLVM: for each target in DIR,
#                  assemble every module with `llc`, generate import
#                  libraries for that machine with `llvm-dlltool` from
#                  `.def` files written here (no Windows SDK is needed or
#                  consulted), link with `lld-link -machine:<m>`, check
#                  the PE's machine type, and read the imports back
#                  through `scripts/lib/imports.sh`'s reader. Then RUN
#                  hello.exe for the runner's own target - TARGET, or the
#                  one `uname -m` names - and require the golden's bytes
#                  and exit 0. The other target is linked and says
#                  "NOT EXECUTED" in its own verdict line.
#
#   --link DIR     the assemble/link/imports part of --run for every
#                  target and NOT the execution, for a host that cannot
#                  run a PE. It prints "not executed" in its own verdict
#                  lines so that it can never be mistaken for the gate.
#
# NO C COMPILER, NO SDK. The Windows path is llc, llvm-dlltool and
# lld-link, by decision (design Q2); `kernel32.lib` is generated from a
# `.def` listing exactly the names on the allowlist, which is also why
# an unpermitted import fails to LINK here before the reader ever sees
# it - the "undefined symbol" lld-link prints is turned into the same
# sentence the allowlist check prints, so the failure names the import.
# One allowlist serves both architectures: the runtime and
# `Sys/Platform.windows.ax` reach the same kernel32 names on each.
#
# NEGATIVE PROBES, per target, in --run and --link:
#   1. (--run, the executed target) the golden, corrupted by one byte,
#      must not match the output the run produced - a comparison that
#      cannot fail is not a comparison;
#   2. the leaky probe - an Axiom program with an `extern "user32"`
#      binding of `MessageBoxA` - is linked against a user32 import
#      library the script generates, and its `.exe` must be REFUSED by
#      the allowlist check. The failure is the passing outcome, exactly
#      as `check-ffi.sh`'s `leaky` crate.

set -euo pipefail

mode="${1:-}"
dir="${2:-}"
run_target="${3:-}"
usage() {
  echo "usage: $0 --emit DIR | --run DIR [windows-x86_64|windows-aarch64] | --link DIR" >&2
  exit 2
}
[[ -n "$mode" && -n "$dir" ]] || usage

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
source "$here/lib/imports.sh"
win_allow="$repo_root/scripts/platform-allow.windows.txt"

win_targets=(windows-x86_64 windows-aarch64)

# The machine each target is spelled as by the three tools that care:
# llvm-dlltool's `-m`, lld-link's `-machine:`, and the COFF header
# `llvm-readobj --file-headers` prints.
dlltool_machine() { case "$1" in windows-x86_64) echo i386:x86-64 ;; windows-aarch64) echo arm64 ;; esac; }
link_machine()    { case "$1" in windows-x86_64) echo x64 ;; windows-aarch64) echo arm64 ;; esac; }
pe_machine()      { case "$1" in windows-x86_64) echo IMAGE_FILE_MACHINE_AMD64 ;; windows-aarch64) echo IMAGE_FILE_MACHINE_ARM64 ;; esac; }
triple_of()       { case "$1" in windows-x86_64) echo x86_64-pc-windows-msvc ;; windows-aarch64) echo aarch64-pc-windows-msvc ;; esac; }

case "$mode" in
  --emit)
    source "$here/lib/gate.sh"
    gate_init
    gate_build_axc axc
    # The leaky probe: user32's MessageBoxA, bound the way any extern is.
    # `(symbol ...)` is spelled so the linker name is unambiguous.
    cat > "$work/leaky.ax" <<'AX'
(import IO)

(pub extern "user32"
  (messageBox :: (-> Int Int Int Int Int) (symbol "MessageBoxA")))

(pub :: main Int)

;@axiom:effect(io)
(pub fn (main)
  {
    (println "leaky")
    (messageBox 0 0 0 0)
    0
  }
)
AX
    for t in "${win_targets[@]}"; do
      d="$dir/$t"
      mkdir -p "$d"
      "$axc" --target="$t" emit-llvm tests/stdlib/010-hello.ax -o "$d/hello.ll"
      cp tests/stdlib/010-hello.out "$d/hello.out"
      "$axc" --target="$t" emit-llvm "$work/leaky.ax" -o "$d/leaky.ll"
      # The allowlist travels with the modules, so the run half compares
      # against the list of THIS commit and not the runner's checkout.
      cp "$win_allow" "$d/platform-allow.windows.txt"
      for f in hello.ll hello.out leaky.ll platform-allow.windows.txt; do
        [[ -s "$d/$f" ]] || { echo "FAIL --emit [$t]: $d/$f is missing or empty"; exit 1; }
      done
      # The module must say which machine it is for: a target that fell
      # through to another's triple would link on the wrong half below.
      for f in hello.ll leaky.ll; do
        if [[ "$(head -1 "$d/$f")" != "target triple = \"$(triple_of "$t")\"" ]]; then
          echo "FAIL --emit [$t]: $d/$f opens with '$(head -1 "$d/$f")', not the $(triple_of "$t") triple"
          exit 1
        fi
      done
      echo "ok   emitted hello.ll and leaky.ll for $t into $d ($(grep -c '^define' "$d/hello.ll") defines in hello, triple $(triple_of "$t"))"
    done
    ;;

  --run|--link)
    for tool in llc lld-link llvm-dlltool llvm-readobj; do
      command -v "$tool" > /dev/null 2>&1 || { echo "FAIL: $tool is not on PATH; the Windows link needs LLVM's llc, lld-link, llvm-dlltool and llvm-readobj"; exit 1; }
    done
    for t in "${win_targets[@]}"; do
      for f in hello.ll hello.out leaky.ll platform-allow.windows.txt; do
        [[ -s "$dir/$t/$f" ]] || { echo "FAIL: $dir/$t/$f is missing or empty; run --emit first"; exit 1; }
      done
    done
    # Which target this runner executes. Named on the command line, or
    # read from the machine; a runner this cannot place is a usage
    # error rather than a guess, since a guess would execute nothing.
    if [[ "$mode" == "--run" ]]; then
      if [[ -z "$run_target" ]]; then
        case "$(uname -m 2>/dev/null)" in
          x86_64|amd64|AMD64) run_target=windows-x86_64 ;;
          aarch64|arm64|ARM64) run_target=windows-aarch64 ;;
          *) echo "FAIL: cannot tell which Windows target this runner executes from \`uname -m\` ($(uname -m 2>/dev/null)); name it: $0 --run DIR <target>"; exit 2 ;;
        esac
      fi
      case "$run_target" in
        windows-x86_64|windows-aarch64) ;;
        *) usage ;;
      esac
    fi
    status=0
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    for t in "${win_targets[@]}"; do
      src="$dir/$t"
      w="$work/$t"
      mkdir -p "$w"
      allow="$src/platform-allow.windows.txt"

      # The import libraries, for this target's machine. kernel32's
      # `.def` is the allowlist itself, so the link can resolve exactly
      # what the list permits; user32's exists for the leaky probe alone.
      { printf 'LIBRARY kernel32.dll\nEXPORTS\n'; permitted_windows "$allow"; } > "$w/kernel32.def"
      printf 'LIBRARY user32.dll\nEXPORTS\nMessageBoxA\n' > "$w/user32.def"
      llvm-dlltool -m "$(dlltool_machine "$t")" -d "$w/kernel32.def" -l "$w/kernel32.lib"
      llvm-dlltool -m "$(dlltool_machine "$t")" -d "$w/user32.def" -l "$w/user32.lib"

      # Assemble and link one module. Prints nothing on success; on a
      # failed link, prints the undefined symbols as the allowlist would.
      link_one() {  # <name> <extra .lib...>
        local name="$1"; shift
        llc -filetype=obj -O1 -relocation-model=pic "$src/$name.ll" -o "$w/$name.obj" 2>"$w/$name.llc.err" \
          || { echo "FAIL $name [$t]: llc refused the module"; sed 's/^/    /' "$w/$name.llc.err" | head -5; return 1; }
        # Dash-form flags, not `/out:`: under Git-bash on the Windows leg,
        # MSYS converts an argument that begins with `/` into a Windows
        # path, and `/out:x.exe` reached lld-link as
        # `C:\Program Files\Git\out;...\x.exe` (the leg's first run,
        # 2026-08-29). lld-link accepts both spellings everywhere.
        if ! lld-link -subsystem:console -entry:mainCRTStartup "-machine:$(link_machine "$t")" "-out:$w/$name.exe" "$w/$name.obj" "$w/kernel32.lib" "$@" >"$w/$name.link.log" 2>&1; then
          echo "FAIL $name [$t]: lld-link failed"
          { grep -o 'undefined symbol: [A-Za-z_][A-Za-z0-9_]*' "$w/$name.link.log" || true; } | sed 's/^/    /' | sort -u
          sed 's/^/    /' "$w/$name.link.log" | head -5
          return 1
        fi
        # The PE says which machine it is for. A module that assembled
        # for the other architecture would already have failed to link
        # against this machine's import library; this reads the answer
        # back rather than inferring it from a link that succeeded.
        # `grep` without `-q`: under `pipefail`, `-q` exiting on the
        # first match can turn the reader's SIGPIPE into a failed test
        # (check-release-targets.sh records the day it did).
        if ! llvm-readobj --file-headers "$w/$name.exe" | grep "Machine: $(pe_machine "$t")" >/dev/null; then
          echo "FAIL $name [$t]: $name.exe is not a $(pe_machine "$t") image: $(llvm-readobj --file-headers "$w/$name.exe" | grep -m1 'Machine:' | tr -s ' ')"
          return 1
        fi
      }

      # 1. hello links, imports only what is permitted, and (--run, on
      #    the runner's own target) runs.
      if link_one hello; then
        imports_of "$w/hello.exe" > "$w/hello.imports"
        n_imports="$(grep -c . "$w/hello.imports" || true)"
        unexpected="$(unpermitted_imports "$w/hello.imports" "$allow")"
        if (( n_imports < 4 )); then
          echo "FAIL hello.exe [$t]: the reader saw $n_imports import(s); the runtime alone needs four, so the reader is not reading"
          status=1
        elif [[ -n "$unexpected" ]]; then
          echo "FAIL hello.exe [$t] imports symbols $allow does not permit:"
          printf '%s\n' "$unexpected" | sed 's/^/    /'
          status=1
        else
          echo "ok   hello.exe [$t] links ($(pe_machine "$t"), $(wc -c < "$w/hello.exe" | tr -d ' ') bytes) and imports only permitted names ($n_imports: $(tr '\n' ' ' < "$w/hello.imports"))"
        fi
        if [[ "$mode" == "--run" && "$t" == "$run_target" ]]; then
          set +e
          "$w/hello.exe" > "$w/hello.stdout" 2> "$w/hello.stderr"
          rc=$?
          set -e
          if [[ "$rc" -ne 0 ]]; then
            echo "FAIL hello.exe [$t] exited $rc, expected 0"
            sed 's/^/    /' "$w/hello.stderr" | head -5
            status=1
          elif ! cmp -s "$w/hello.stdout" "$src/hello.out"; then
            echo "FAIL hello.exe [$t]'s stdout is not the golden's bytes"
            { diff "$src/hello.out" "$w/hello.stdout" || true; } | head -10 | sed 's/^/    /'
            status=1
          else
            echo "ok   hello.exe [$t] EXECUTED on $(uname -s 2>/dev/null || echo windows): exit 0 and $(wc -c < "$w/hello.stdout" | tr -d ' ') bytes of stdout equal to tests/stdlib/010-hello.out"
            # Probe 1: the comparison can fail.
            { cat "$src/hello.out"; printf 'x'; } > "$w/hello.out.corrupt"
            if cmp -s "$w/hello.stdout" "$w/hello.out.corrupt"; then
              echo "FAIL negative probe [$t]: a corrupted golden still matched the output"
              status=1
            else
              echo "ok   negative probe [$t]: a corrupted golden does not match the output"
            fi
          fi
        elif [[ "$mode" == "--run" ]]; then
          echo "ok   hello.exe [$t] NOT EXECUTED: this runner executes $run_target; $t is linked and its imports read"
        else
          echo "ok   hello.exe [$t] NOT EXECUTED: --link assembles, links and reads imports on a host that cannot run a PE; a Windows runner runs --run"
        fi
      else
        status=1
      fi

      # 2. The leaky probe links (user32.lib is on its line) and is refused.
      if link_one leaky "$w/user32.lib"; then
        imports_of "$w/leaky.exe" > "$w/leaky.imports"
        leaked="$(unpermitted_imports "$w/leaky.imports" "$allow" | tr '\n' ' ')"
        if [[ "$leaked" == "MessageBoxA " ]]; then
          echo "ok   negative probe [$t]: leaky.exe imports MessageBoxA and the allowlist refuses it"
        else
          echo "FAIL negative probe [$t]: leaky.exe's unpermitted imports were '$leaked', expected MessageBoxA alone"
          status=1
        fi
      else
        echo "FAIL negative probe [$t]: the leaky probe did not link, so the allowlist was never shown refusing a real executable"
        status=1
      fi
    done
    exit "$status"
    ;;
  *) usage ;;
esac
