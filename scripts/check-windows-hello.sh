#!/usr/bin/env bash
# A hello world for windows-x86_64: emitted on any host, linked and
# EXECUTED on a Windows runner, its output compared byte for byte with
# the golden, and its imports held to `scripts/platform-allow.windows.txt`.
#
# This is the gate that decides whether windows-x86_64 is on its way to
# being supported at all - README's Targets section defines supported as
# "a CI leg executes what the compiler emits there", and this is the
# executing. It runs in two halves, on two machines, because the two
# halves need two toolchains:
#
#   --emit DIR     on a host with the tree's compiler: emit the hello
#                  case and the leaky probe for windows-x86_64 into DIR,
#                  beside the golden they must answer. The `cross` CI job
#                  does this on Linux and uploads DIR as an artifact.
#
#   --run DIR      on a Windows runner with LLVM: assemble every module
#                  in DIR with `llc`, generate import libraries with
#                  `llvm-dlltool` from `.def` files written here (no
#                  Windows SDK is needed or consulted), link with
#                  `lld-link`, read the imports back through
#                  `scripts/lib/imports.sh`'s reader, RUN hello.exe, and
#                  require the golden's bytes and exit 0.
#
#   --link DIR     the assemble/link/imports part of --run and NOT the
#                  execution, for a host that cannot run a PE. It prints
#                  "not executed" in its own verdict line so that it can
#                  never be mistaken for the gate; the CI leg uses --run.
#
# NO C COMPILER, NO SDK. The Windows path is llc, llvm-dlltool and
# lld-link, by decision (design Q2); `kernel32.lib` is generated from a
# `.def` listing exactly the names on the allowlist, which is also why
# an unpermitted import fails to LINK here before the reader ever sees
# it - the "undefined symbol" lld-link prints is turned into the same
# sentence the allowlist check prints, so the failure names the import.
#
# NEGATIVE PROBES, both in --run and --link:
#   1. the golden, corrupted by one byte, must not match the output the
#      run produced - a comparison that cannot fail is not a comparison;
#   2. the leaky probe - an Axiom program with an `extern "user32"`
#      binding of `MessageBoxA` - is linked against a user32 import
#      library the script generates, and its `.exe` must be REFUSED by
#      the allowlist check. The failure is the passing outcome, exactly
#      as `check-ffi.sh`'s `leaky` crate.

set -euo pipefail

mode="${1:-}"
dir="${2:-}"
usage() {
  echo "usage: $0 --emit DIR | --run DIR | --link DIR" >&2
  exit 2
}
[[ -n "$mode" && -n "$dir" ]] || usage

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
source "$here/lib/imports.sh"
win_allow="$repo_root/scripts/platform-allow.windows.txt"

case "$mode" in
  --emit)
    source "$here/lib/gate.sh"
    gate_init
    gate_build_axc axc
    mkdir -p "$dir"
    "$axc" --target=windows-x86_64 emit-llvm tests/stdlib/010-hello.ax -o "$dir/hello.ll"
    cp tests/stdlib/010-hello.out "$dir/hello.out"
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
    "$axc" --target=windows-x86_64 emit-llvm "$work/leaky.ax" -o "$dir/leaky.ll"
    # The allowlist travels with the modules, so the run half compares
    # against the list of THIS commit and not the runner's checkout.
    cp "$win_allow" "$dir/platform-allow.windows.txt"
    for f in hello.ll hello.out leaky.ll platform-allow.windows.txt; do
      [[ -s "$dir/$f" ]] || { echo "FAIL --emit: $dir/$f is missing or empty"; exit 1; }
    done
    echo "ok   emitted hello.ll and leaky.ll for windows-x86_64 into $dir ($(grep -c '^define' "$dir/hello.ll") defines in hello)"
    ;;

  --run|--link)
    for tool in llc lld-link llvm-dlltool llvm-readobj; do
      command -v "$tool" > /dev/null 2>&1 || { echo "FAIL: $tool is not on PATH; the Windows link needs LLVM's llc, lld-link, llvm-dlltool and llvm-readobj"; exit 1; }
    done
    for f in hello.ll hello.out leaky.ll platform-allow.windows.txt; do
      [[ -s "$dir/$f" ]] || { echo "FAIL: $dir/$f is missing or empty; run --emit first"; exit 1; }
    done
    allow="$dir/platform-allow.windows.txt"
    status=0
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    # The import libraries. kernel32's `.def` is the allowlist itself,
    # so the link can resolve exactly what the list permits; user32's
    # exists for the leaky probe alone.
    { printf 'LIBRARY kernel32.dll\nEXPORTS\n'; permitted_windows "$allow"; } > "$work/kernel32.def"
    printf 'LIBRARY user32.dll\nEXPORTS\nMessageBoxA\n' > "$work/user32.def"
    llvm-dlltool -m i386:x86-64 -d "$work/kernel32.def" -l "$work/kernel32.lib"
    llvm-dlltool -m i386:x86-64 -d "$work/user32.def" -l "$work/user32.lib"

    # Assemble and link one module. Prints nothing on success; on a
    # failed link, prints the undefined symbols as the allowlist would.
    link_one() {  # <name> <extra .lib...>
      local name="$1"; shift
      llc -filetype=obj -O1 -relocation-model=pic "$dir/$name.ll" -o "$work/$name.obj" 2>"$work/$name.llc.err" \
        || { echo "FAIL $name: llc refused the module"; sed 's/^/    /' "$work/$name.llc.err" | head -5; return 1; }
      # Dash-form flags, not `/out:`: under Git-bash on the Windows leg,
      # MSYS converts an argument that begins with `/` into a Windows
      # path, and `/out:x.exe` reached lld-link as
      # `C:\Program Files\Git\out;...\x.exe` (the leg's first run,
      # 2026-08-29). lld-link accepts both spellings everywhere.
      if ! lld-link -subsystem:console -entry:mainCRTStartup "-out:$work/$name.exe" "$work/$name.obj" "$work/kernel32.lib" "$@" >"$work/$name.link.log" 2>&1; then
        echo "FAIL $name: lld-link failed"
        grep -o 'undefined symbol: [A-Za-z_][A-Za-z0-9_]*' "$work/$name.link.log" | sed 's/^/    /' | sort -u
        sed 's/^/    /' "$work/$name.link.log" | head -5
        return 1
      fi
    }

    # 1. hello links, imports only what is permitted, and (--run) runs.
    if link_one hello; then
      imports_of "$work/hello.exe" > "$work/hello.imports"
      n_imports="$(grep -c . "$work/hello.imports" || true)"
      unexpected="$(unpermitted_imports "$work/hello.imports" "$allow")"
      if (( n_imports < 4 )); then
        echo "FAIL hello.exe: the reader saw $n_imports import(s); the runtime alone needs four, so the reader is not reading"
        status=1
      elif [[ -n "$unexpected" ]]; then
        echo "FAIL hello.exe imports symbols $allow does not permit:"
        printf '%s\n' "$unexpected" | sed 's/^/    /'
        status=1
      else
        echo "ok   hello.exe links ($(wc -c < "$work/hello.exe" | tr -d ' ') bytes) and imports only permitted names ($n_imports: $(tr '\n' ' ' < "$work/hello.imports"))"
      fi
      if [[ "$mode" == "--run" ]]; then
        set +e
        "$work/hello.exe" > "$work/hello.stdout" 2> "$work/hello.stderr"
        rc=$?
        set -e
        if [[ "$rc" -ne 0 ]]; then
          echo "FAIL hello.exe exited $rc, expected 0"
          sed 's/^/    /' "$work/hello.stderr" | head -5
          status=1
        elif ! cmp -s "$work/hello.stdout" "$dir/hello.out"; then
          echo "FAIL hello.exe's stdout is not the golden's bytes"
          { diff "$dir/hello.out" "$work/hello.stdout" || true; } | head -10 | sed 's/^/    /'
          status=1
        else
          echo "ok   hello.exe EXECUTED on $(uname -s 2>/dev/null || echo windows): exit 0 and $(wc -c < "$work/hello.stdout" | tr -d ' ') bytes of stdout equal to tests/stdlib/010-hello.out"
          # Probe 1: the comparison can fail.
          { cat "$dir/hello.out"; printf 'x'; } > "$work/hello.out.corrupt"
          if cmp -s "$work/hello.stdout" "$work/hello.out.corrupt"; then
            echo "FAIL negative probe: a corrupted golden still matched the output"
            status=1
          else
            echo "ok   negative probe: a corrupted golden does not match the output"
          fi
        fi
      else
        echo "ok   hello.exe NOT EXECUTED: --link assembles, links and reads imports on a host that cannot run a PE; the CI leg runs --run"
      fi
    else
      status=1
    fi

    # 2. The leaky probe links (user32.lib is on its line) and is refused.
    if link_one leaky "$work/user32.lib"; then
      imports_of "$work/leaky.exe" > "$work/leaky.imports"
      leaked="$(unpermitted_imports "$work/leaky.imports" "$allow" | tr '\n' ' ')"
      if [[ "$leaked" == "MessageBoxA " ]]; then
        echo "ok   negative probe: leaky.exe imports MessageBoxA and the allowlist refuses it"
      else
        echo "FAIL negative probe: leaky.exe's unpermitted imports were '$leaked', expected MessageBoxA alone"
        status=1
      fi
    else
      echo "FAIL negative probe: the leaky probe did not link, so the allowlist was never shown refusing a real executable"
      status=1
    fi
    exit "$status"
    ;;
  *) usage ;;
esac
