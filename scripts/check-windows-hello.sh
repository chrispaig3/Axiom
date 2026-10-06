#!/usr/bin/env bash
# A hello world for both Windows targets, windows-x86_64 and
# windows-aarch64. It is emitted on any host, then linked and executed on
# a Windows runner. Its output must match the golden byte for byte, and
# its imports must stay within `scripts/platform-allow.windows.txt`.
#
# README's Targets section calls a target supported when "a CI job
# executes what the compiler emits there". For Windows, this gate is
# that execution. It runs in two halves on two machines, because each
# half needs its own toolchain:
#
#   --emit DIR     on a host with the tree's compiler: emit the hello
#                  case and the leaky probe for each Windows target into
#                  DIR/<target>/, beside the golden they must match. The
#                  `cross` CI job runs this half.
#
#   --run DIR [TARGET]
#                  on a Windows runner with LLVM, for each target in DIR:
#                  assemble each module with `llc`, generate import
#                  libraries with `llvm-dlltool` from `.def` files written
#                  here, link with `lld-link -machine:<m>`, check the PE's
#                  machine type, and read the imports back through
#                  `scripts/lib/imports.sh`. Then run hello.exe for the
#                  runner's own target (TARGET, or the one `uname -m`
#                  names) and require exit 0 and the golden's bytes. The
#                  other target is linked and reports "NOT EXECUTED".
#
#   --link DIR     everything --run does except execution, for a host
#                  that cannot run a PE. Its verdict lines say "not
#                  executed", so it is never mistaken for the gate.
#
# No C compiler and no Windows SDK: the path is llc, llvm-dlltool and
# lld-link (design Q2). `kernel32.lib` is generated from a `.def` listing
# exactly the allowlisted names, so an unpermitted kernel32 import fails
# to link before the import reader sees it. The script prints lld-link's
# undefined symbols, so that failure still names the import. One
# allowlist serves both architectures, because the runtime and
# `Sys/Platform.windows.ax` reach the same kernel32 names on each.
#
# Negative probes, per target:
#   1. (--run, executed target only) the golden with one byte appended
#      must not match the output, so the comparison can fail.
#   2. The leaky probe binds user32's `MessageBoxA` through `extern` and
#      links against a generated user32 import library. The allowlist
#      check must refuse its `.exe`: that refusal is the passing outcome,
#      as with `check-ffi.sh`'s `leaky` crate.

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

# How each tool spells a target's machine: llvm-dlltool's `-m`,
# lld-link's `-machine:` and the COFF header `llvm-readobj
# --file-headers` prints.
dlltool_machine() { case "$1" in windows-x86_64) echo i386:x86-64 ;; windows-aarch64) echo arm64 ;; esac; }
link_machine()    { case "$1" in windows-x86_64) echo x64 ;; windows-aarch64) echo arm64 ;; esac; }
pe_machine()      { case "$1" in windows-x86_64) echo IMAGE_FILE_MACHINE_AMD64 ;; windows-aarch64) echo IMAGE_FILE_MACHINE_ARM64 ;; esac; }
triple_of()       { case "$1" in windows-x86_64) echo x86_64-pc-windows-msvc ;; windows-aarch64) echo aarch64-pc-windows-msvc ;; esac; }

case "$mode" in
  --emit)
    source "$here/lib/gate.sh"
    gate_init
    gate_build_axc axc
    # The leaky probe binds user32's MessageBoxA like any other extern.
    # `(symbol ...)` pins the linker name.
    cat > "$work/leaky.ax" <<'AX'
(import IO)

(pub extern "user32"
  (messageBox :: (-> Int Int Int Int Int) (symbol "MessageBoxA")))

(pub :: main Int)

;@axiom:effect(io)
;@axiom:effect(unsafe)
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
      # The allowlist travels with the modules, so the run half checks
      # against this commit's list rather than the runner's checkout.
      cp "$win_allow" "$d/platform-allow.windows.txt"
      for f in hello.ll hello.out leaky.ll platform-allow.windows.txt; do
        [[ -s "$d/$f" ]] || { echo "FAIL --emit [$t]: $d/$f is missing or empty"; exit 1; }
      done
      # Each module must open with its own target's triple. A target that
      # fell through to another's triple would be assembled for the wrong
      # machine.
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
    # Which target this runner executes: named on the command line, or
    # read from `uname -m`. An unknown machine is a usage error, since a
    # wrong guess would execute nothing.
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

      # Import libraries for this target's machine. kernel32's `.def` is
      # the allowlist, so the link resolves exactly what the list
      # permits. user32's exists only for the leaky probe.
      { printf 'LIBRARY kernel32.dll\nEXPORTS\n'; permitted_windows "$allow"; } > "$w/kernel32.def"
      printf 'LIBRARY user32.dll\nEXPORTS\nMessageBoxA\n' > "$w/user32.def"
      llvm-dlltool -m "$(dlltool_machine "$t")" -d "$w/kernel32.def" -l "$w/kernel32.lib"
      llvm-dlltool -m "$(dlltool_machine "$t")" -d "$w/user32.def" -l "$w/user32.lib"

      # Assemble and link one module. Silent on success; a failed link
      # prints its undefined symbols.
      link_one() {  # <name> <extra .lib...>
        local name="$1"; shift
        llc -filetype=obj -O1 -relocation-model=pic "$src/$name.ll" -o "$w/$name.obj" 2>"$w/$name.llc.err" \
          || { echo "FAIL $name [$t]: llc refused the module"; sed 's/^/    /' "$w/$name.llc.err" | head -5; return 1; }
        # Use dash-form flags such as `-out:`. Under Git Bash, MSYS turns
        # an argument starting with `/` into a Windows path, so `/out:x.exe`
        # reaches lld-link as `C:\Program Files\Git\out;...\x.exe`.
        # lld-link accepts both spellings.
        if ! lld-link -subsystem:console -entry:mainCRTStartup "-machine:$(link_machine "$t")" "-out:$w/$name.exe" "$w/$name.obj" "$w/kernel32.lib" "$@" >"$w/$name.link.log" 2>&1; then
          echo "FAIL $name [$t]: lld-link failed"
          { grep -o 'undefined symbol: [A-Za-z_][A-Za-z0-9_]*' "$w/$name.link.log" || true; } | sed 's/^/    /' | sort -u
          sed 's/^/    /' "$w/$name.link.log" | head -5
          return 1
        fi
        # Read the PE's machine type back instead of inferring it from a
        # successful link. `grep` without `-q`: under `pipefail`, `-q`
        # exits on the first match and the reader's SIGPIPE can fail the
        # pipeline.
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
