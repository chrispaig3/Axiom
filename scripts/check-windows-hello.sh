#!/usr/bin/env bash
# The Windows targets, windows-x86_64 and windows-aarch64: emitted on any
# host, then linked on Windows runners and executed on each runner's
# own architecture. Six things run:
#
#   1. A hello world for each target. Its output must match the golden
#      byte for byte, and its imports must stay within
#      `scripts/platform-allow.windows.txt`.
#   2. The compiler itself, emitted for each target and linked with
#      an 8 MB stack. It emits `core/main.ax` again byte for byte,
#      builds and runs the hello case through its own driver, and
#      reports `tests/testrunner/mixed-tests.ax` to its golden.
#   3. `examples/tree-audit/tree-audit.ax`, built and run by that
#      compiler over a fixture tree. Its report must equal the one the
#      emitting host printed, which a Python oracle checked there.
#   4. A large-frame fixture that requires the runtime's stack probe,
#      followed by the standard-library battery.
#   5. Console input and control-event probes in their own consoles,
#      with synthetic input and no interactive desktop requirement.
#   6. Encoded workers at O0 and O2: process isolation, bounded results,
#      deadlines and live cancellation through an executable endpoint.
#
# README's Targets section calls a target supported when "a CI job
# executes what the compiler emits there". For Windows, this gate is
# that execution. It runs in two halves on two machines, because each
# half needs its own toolchain:
#
#   --emit DIR     on a host with the tree's compiler: emit the hello
#                  case, leaky probe and large-frame fixture for each Windows target into
#                  DIR/<target>/, beside the golden they must match, and
#                  the compiler and the tree audit's report into
#                  DIR/selfhost/. Encoded-worker modules and their
#                  allowlist go into DIR/encoded-workers/. The `cross`
#                  CI job runs this half.
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
#                  Then link the compiler, and run parts 2, 3 and the
#                  library battery for the runner's own target.
#
#   --link DIR     everything --run does except execution, for a host
#                  that cannot run a PE. Its verdict lines say "not
#                  executed", so it is never mistaken for the gate.
#
# No C compiler and no Windows SDK: the path is llc, llvm-dlltool and
# lld-link (design Q2). One import library per DLL the allowlist names
# is generated from a `.def` listing exactly that DLL's allowlisted
# names (kernel32's, and `name@dll` entries for any other, such as
# bcryptprimitives' `ProcessPrng`), so an unpermitted import fails to
# link before the import reader sees it. The script prints lld-link's
# undefined symbols, so that failure still names the import. One
# allowlist serves both architectures, because the runtime and
# `Sys/Platform.windows.ax` reach the same names on each.
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
worker_fixtures=(encoded-worker-endpoint encoded-worker-pool encoded-worker-cancel)

# How each tool spells a target's machine: llvm-dlltool's `-m`,
# lld-link's `-machine:` and the COFF header `llvm-readobj
# --file-headers` prints.
dlltool_machine() { case "$1" in windows-x86_64) echo i386:x86-64 ;; windows-aarch64) echo arm64 ;; esac; }
link_machine()    { case "$1" in windows-x86_64) echo x64 ;; windows-aarch64) echo arm64 ;; esac; }
pe_machine()      { case "$1" in windows-x86_64) echo IMAGE_FILE_MACHINE_AMD64 ;; windows-aarch64) echo IMAGE_FILE_MACHINE_ARM64 ;; esac; }
triple_of()       { case "$1" in windows-x86_64) echo x86_64-pc-windows-msvc ;; windows-aarch64) echo aarch64-pc-windows-msvc ;; esac; }

# Keep the actual result ahead of a bounded diff: a long omitted block
# in a normal diff can otherwise hide every failed assertion and errno.
console_failure() {  # <probe> <target> <exit> <expected> <stdout> <stderr>
  local probe="$1" target="$2" rc="$3" expected="$4" actual="$5" errors="$6"
  local saved="$dir/failures/$target/$probe"
  mkdir -p "$saved"
  cp "$expected" "$saved/expected.stdout"
  cp "$actual" "$saved/actual.stdout"
  cp "$errors" "$saved/actual.stderr"
  printf '%s\n' "$rc" > "$saved/exit-status.txt"
  echo "    actual stdout:"
  sed 's/^/    /' "$actual"
  echo "    actual stderr:"
  sed 's/^/    /' "$errors"
  echo "    expected/actual diff (first 80 lines):"
  { diff -u "$expected" "$actual" || true; } | sed -n '1,80s/^/    /p'
  echo "    failure logs: $saved"
}

# The tree the auditor reads, written the same way on every host: a
# file with CRLF line ends that must not be translated, an empty file,
# every byte value, a UTF-8 name, and two names whose byte order is not
# their alphabetical order.
tree_fixture() {  # <dir>
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/docs" "$d/src/nested"
  printf 'hello\n' > "$d/README"
  printf 'line one\r\nline two\r\n' > "$d/docs/crlf.txt"
  : > "$d/docs/empty"
  printf '(:: main ())\n' > "$d/src/main.ax"
  printf 'upper\n' > "$d/src/B"
  printf 'lower\n' > "$d/src/a"
  local i
  for i in $(seq 0 255); do printf "\\$(printf '%03o' "$i")"; done > "$d/src/nested/bytes.bin"
  printf 'caf\303\251\n' > "$d/src/nested/caf$(printf '\303\251').txt"
}

# The report `tree-audit.ax` must print for <dir>, computed by Python
# from the same rule: names in byte order, `/` between path components,
# and one SHA-256 over every file line.
tree_oracle() {  # <dir>
  python3 -I - "$1" <<'PY'
import hashlib, os, sys
lines, count = [], {'dirs': 0, 'bytes': 0}
def walk(d, rel):
    count['dirs'] += 1
    for name in sorted(os.listdir(d), key=os.fsencode):
        path = os.path.join(d, name)
        shown = name if not rel else rel + '/' + name
        if os.path.isdir(path):
            walk(path, shown)
            continue
        with open(path, 'rb') as f:
            data = f.read()
        count['bytes'] += len(data)
        digest = hashlib.sha256(data).hexdigest().encode()
        lines.append(b'%s %d %s' % (digest, len(data), os.fsencode(shown)))
walk(sys.argv[1], '')
listing = b''.join(line + b'\n' for line in lines)
tree = hashlib.sha256(listing).hexdigest().encode()
summary = b'dirs %d\nfiles %d\nbytes %d\ntree %s\n' % (count['dirs'], len(lines), count['bytes'], tree)
sys.stdout.buffer.write(listing + summary)
PY
}

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
    python3 "$repo_root/tests/recover/windows-stack-probe.py" source "$work/large-frame.ax"
    for t in "${win_targets[@]}"; do
      d="$dir/$t"
      mkdir -p "$d"
      "$axc" --target="$t" emit-llvm tests/stdlib/010-hello.ax -o "$d/hello.ll"
      cp tests/stdlib/010-hello.out "$d/hello.out"
      "$axc" --target="$t" emit-llvm "$work/leaky.ax" -o "$d/leaky.ll"
      "$axc" --diagnostic-format=ai --target="$t" emit-llvm "$work/large-frame.ax" -o "$d/large-frame.ll"
      cp "$work/large-frame.out" "$d/large-frame.out"
      for probe in windows-console windows-controls; do
        "$axc" --diagnostic-format=ai --target="$t" emit-llvm "tests/platform/$probe.ax" -o "$d/$probe.ll"
        cp "tests/platform/$probe.out" "$d/$probe.out"
      done
      # The allowlist travels with the modules, so the run half checks
      # against this commit's list rather than the runner's checkout.
      cp "$win_allow" "$d/platform-allow.windows.txt"
      cat "$win_allow" "$repo_root/tests/platform/windows-console-imports.txt" > "$d/console-probe-allow.txt"
      for f in hello.ll hello.out leaky.ll large-frame.ll large-frame.out windows-console.ll windows-console.out windows-controls.ll windows-controls.out platform-allow.windows.txt console-probe-allow.txt; do
        [[ -s "$d/$f" ]] || { echo "FAIL --emit [$t]: $d/$f is missing or empty"; exit 1; }
      done
      # Each module must open with its own target's triple. A target that
      # fell through to another's triple would be assembled for the wrong
      # machine.
      for f in hello.ll leaky.ll large-frame.ll windows-console.ll windows-controls.ll; do
        if [[ "$(head -1 "$d/$f")" != "target triple = \"$(triple_of "$t")\"" ]]; then
          echo "FAIL --emit [$t]: $d/$f opens with '$(head -1 "$d/$f")', not the $(triple_of "$t") triple"
          exit 1
        fi
      done
      echo "ok   emitted hello.ll and leaky.ll for $t into $d ($(grep -c '^define' "$d/hello.ll") defines in hello, triple $(triple_of "$t"))"
    done
    python3 "$repo_root/tests/platform/worker-pool.py" --axiom "$axc" --emit-windows "$dir/encoded-workers"
    [[ -s "$dir/encoded-workers/platform-allow.windows.txt" ]] || { echo "FAIL --emit: the encoded-worker allowlist is missing or empty"; exit 1; }
    for t in "${win_targets[@]}"; do
      for fixture in "${worker_fixtures[@]}"; do
        f="$dir/encoded-workers/$t/$fixture.ll"
        if [[ ! -s "$f" || "$(head -1 "$f")" != "target triple = \"$(triple_of "$t")\"" ]]; then
          echo "FAIL --emit [$t]: $f is missing, empty or has the wrong target triple"
          exit 1
        fi
      done
      echo "ok   emitted the encoded-worker endpoint, pool and cancellation fixtures for $t"
    done
    # 2. The compiler, for each Windows target a runner executes. The
    #    runner's own build of it must emit this again, byte for byte.
    sh="$dir/selfhost"
    mkdir -p "$sh"
    for t in "${win_targets[@]}"; do
      "$axc" --target="$t" emit-llvm core/main.ax -o "$sh/axiom-$t.ll"
      if [[ "$(head -1 "$sh/axiom-$t.ll")" != "target triple = \"$(triple_of "$t")\"" ]]; then
        echo "FAIL --emit: the compiler's IR for $t opens with '$(head -1 "$sh/axiom-$t.ll")', not the $(triple_of "$t") triple"
        exit 1
      fi
      echo "ok   emitted the compiler for $t into $sh ($(grep -c '^define' "$sh/axiom-$t.ll") defines)"
    done
    # 3. The tree audit's report over the fixture, from this host's
    #    compiler, held to an independent oracle before it travels.
    tree_fixture "$work/tree"
    "$axc" run examples/tree-audit/tree-audit.ax "$work/tree" > "$sh/tree-audit.out"
    tree_oracle "$work/tree" > "$work/tree-oracle.out"
    if ! cmp -s "$sh/tree-audit.out" "$work/tree-oracle.out"; then
      echo "FAIL --emit: the tree audit's report is not the oracle's"
      { diff "$work/tree-oracle.out" "$sh/tree-audit.out" || true; } | head -10 | sed 's/^/    /'
      exit 1
    fi
    echo "ok   the tree audit's report over the fixture equals the oracle's ($(grep -c . "$sh/tree-audit.out") lines)"
    ;;

  --run|--link)
    for tool in llc opt lld-link llvm-dlltool llvm-readobj python3; do
      command -v "$tool" > /dev/null 2>&1 || { echo "FAIL: $tool is not on PATH; the Windows link needs Python 3 and LLVM's llc, opt, lld-link, llvm-dlltool and llvm-readobj"; exit 1; }
    done
    for t in "${win_targets[@]}"; do
      for f in hello.ll hello.out leaky.ll large-frame.ll large-frame.out windows-console.ll windows-console.out windows-controls.ll windows-controls.out platform-allow.windows.txt console-probe-allow.txt; do
        [[ -s "$dir/$t/$f" ]] || { echo "FAIL: $dir/$t/$f is missing or empty; run --emit first"; exit 1; }
      done
      for fixture in "${worker_fixtures[@]}"; do
        [[ -s "$dir/encoded-workers/$t/$fixture.ll" ]] || { echo "FAIL: $dir/encoded-workers/$t/$fixture.ll is missing or empty; run --emit first"; exit 1; }
      done
    done
    [[ -s "$dir/encoded-workers/platform-allow.windows.txt" ]] || { echo "FAIL: the encoded-worker allowlist is missing or empty; run --emit first"; exit 1; }
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

      # Import libraries for this target's machine, one per DLL the
      # allowlist names: each `.def` is that DLL's permitted names, so
      # the link resolves exactly what the list permits. user32's
      # exists only for the leaky probe.
      implibs=()
      for dll in $(permitted_windows_dlls "$allow"); do
        { printf 'LIBRARY %s.dll\nEXPORTS\n' "$dll"; permitted_windows_for_dll "$allow" "$dll"; } > "$w/$dll.def"
        llvm-dlltool -m "$(dlltool_machine "$t")" -d "$w/$dll.def" -l "$w/$dll.lib"
        implibs+=("$w/$dll.lib")
      done
      printf 'LIBRARY user32.dll\nEXPORTS\nMessageBoxA\n' > "$w/user32.def"
      llvm-dlltool -m "$(dlltool_machine "$t")" -d "$w/user32.def" -l "$w/user32.lib"
      # Only the console probes may create a console and inject input.
      # Keep those fixture APIs out of the production import allowlist.
      probe_allow="$src/console-probe-allow.txt"
      { printf 'LIBRARY kernel32.dll\nEXPORTS\n'; permitted_windows_for_dll "$probe_allow" kernel32; } > "$w/console-probe.def"
      llvm-dlltool -m "$(dlltool_machine "$t")" -d "$w/console-probe.def" -l "$w/console-probe.lib"

      # Assemble and link one module. Silent on success; a failed link
      # prints its undefined symbols.
      link_one() {  # <name> <llc level> <extra .lib...>
        local name="$1" level="$2"; shift 2
        llc -filetype=obj "-O$level" -relocation-model=pic "$src/$name.ll" -o "$w/$name.obj" 2>"$w/$name.llc.err" \
          || { echo "FAIL $name [$t]: llc refused the module"; sed 's/^/    /' "$w/$name.llc.err" | head -5; return 1; }
        # Use dash-form flags such as `-out:`. Under Git Bash, MSYS turns
        # an argument starting with `/` into a Windows path, so `/out:x.exe`
        # reaches lld-link as `C:\Program Files\Git\out;...\x.exe`.
        # lld-link accepts both spellings.
        if ! lld-link -subsystem:console -entry:mainCRTStartup "-machine:$(link_machine "$t")" "-out:$w/$name.exe" "$w/$name.obj" "${implibs[@]}" "$@" >"$w/$name.link.log" 2>&1; then
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
      if link_one hello 1; then
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
        elif [[ -n "$(misplaced_imports "$w/hello.exe" "$allow")" ]]; then
          echo "FAIL hello.exe [$t] imports a permitted name from another DLL than $allow says:"
          misplaced_imports "$w/hello.exe" "$allow" | sed 's/^/    /'
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
      if link_one leaky 1 "$w/user32.lib"; then
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

      # -O0 keeps this call frame larger than a page, requiring the
      # runtime's __chkstk helper. Link both machines, execute the
      # runner's own machine, and keep cross-linking explicit.
      if link_one large-frame 0; then
        if [[ "$mode" == "--run" && "$t" == "$run_target" ]]; then
          rc=0
          "$w/large-frame.exe" > "$w/large-frame.stdout" 2> "$w/large-frame.stderr" || rc=$?
          if [[ "$rc" -eq 0 ]] && cmp -s "$w/large-frame.stdout" "$src/large-frame.out"; then
            echo "ok   large-frame.exe [$t] EXECUTED: exit 0 and the expected result with a stack probe"
          else
            echo "FAIL large-frame.exe [$t]: exit $rc or output differs from the expected result"
            head -5 "$w/large-frame.stderr" | sed 's/^/    /'
            status=1
          fi
        else
          echo "ok   large-frame.exe [$t] links with __chkstk; NOT EXECUTED on this host"
        fi
      else
        status=1
      fi
      for probe in windows-console windows-controls; do
        if link_one "$probe" 1 "$w/console-probe.lib"; then
          imports_of "$w/$probe.exe" > "$w/$probe.imports"
          unexpected="$(unpermitted_imports "$w/$probe.imports" "$probe_allow")"
          wrong_dll="$(misplaced_imports "$w/$probe.exe" "$probe_allow")"
          if [[ -n "$unexpected" || -n "$wrong_dll" ]]; then
            echo "FAIL $probe [$t]: imports outside the console probe's allowlist: $unexpected $wrong_dll"
            status=1
          elif [[ "$mode" == "--run" && "$t" == "$run_target" ]]; then
            rc=0
            timeout 30 "$w/$probe.exe" > "$w/$probe.stdout" 2> "$w/$probe.stderr" || rc=$?
            if [[ "$rc" -eq 0 && ! -s "$w/$probe.stderr" ]] && cmp -s "$w/$probe.stdout" "$src/$probe.out"; then
              echo "ok   $probe.exe [$t] EXECUTED: exit 0 and the expected console events"
            else
              echo "FAIL $probe.exe [$t]: exit $rc or console events differ from the expected result"
              console_failure "$probe" "$t" "$rc" "$src/$probe.out" "$w/$probe.stdout" "$w/$probe.stderr"
              status=1
            fi
          else
            echo "ok   $probe.exe [$t] links with only permitted probe APIs; NOT EXECUTED on this host"
          fi
        else
          status=1
        fi
      done
    done

    if [[ "$mode" == "--run" ]]; then
      if ! python3 "$repo_root/tests/platform/worker-pool.py" --run-windows "$dir/encoded-workers" --target "$run_target"; then
        echo "FAIL encoded workers on $run_target"
        status=1
      fi
    elif ! python3 "$repo_root/tests/platform/worker-pool.py" --link-windows "$dir/encoded-workers"; then
      echo "FAIL encoded-worker cross-links"
      status=1
    fi

    # 2 and 3. The compiler, linked the way the driver links a Windows
    # executable: for both targets under --link, and under --run for the
    # one this runner executes, which then runs it.
    sh="$dir/selfhost"
    [[ -s "$sh/tree-audit.out" ]] || { echo "FAIL: $sh/tree-audit.out is missing or empty; run --emit first"; exit 1; }
    if [[ "$mode" == "--run" ]]; then link_targets=("$run_target"); else link_targets=("${win_targets[@]}"); fi
    for t in "${link_targets[@]}"; do
      allow="$dir/$t/platform-allow.windows.txt"
      [[ -s "$sh/axiom-$t.ll" ]] || { echo "FAIL: $sh/axiom-$t.ll is missing or empty; run --emit first"; exit 1; }
      w="$work/selfhost-$t"
      mkdir -p "$w"
      implibs=()
      for dll in $(permitted_windows_dlls "$allow"); do
        { printf 'LIBRARY %s.dll\nEXPORTS\n' "$dll"; permitted_windows_for_dll "$allow" "$dll"; } > "$w/$dll.def"
        llvm-dlltool -m "$(dlltool_machine "$t")" -d "$w/$dll.def" -l "$w/$dll.lib"
        implibs+=("$w/$dll.lib")
      done
      if ! llc -filetype=obj -O1 -relocation-model=pic "$sh/axiom-$t.ll" -o "$w/axiom.obj" 2>"$w/axiom.llc.err"; then
        echo "FAIL axiom.exe [$t]: llc refused the compiler's IR"
        sed 's/^/    /' "$w/axiom.llc.err" | head -5
        exit 1
      fi
      # The 8 MB stack the driver gives every Windows executable. The
      # compiler overflows Windows' 1 MB default compiling itself.
      if ! lld-link -subsystem:console -entry:mainCRTStartup "-machine:$(link_machine "$t")" -stack:8388608 "-out:$w/axiom.exe" "$w/axiom.obj" "${implibs[@]}" >"$w/axiom.link.log" 2>&1; then
        echo "FAIL axiom.exe [$t]: lld-link failed"
        { grep -o 'undefined symbol: [A-Za-z_][A-Za-z0-9_]*' "$w/axiom.link.log" || true; } | sed 's/^/    /' | sort -u
        sed 's/^/    /' "$w/axiom.link.log" | head -5
        exit 1
      fi
      imports_of "$w/axiom.exe" > "$w/axiom.imports"
      unexpected="$(unpermitted_imports "$w/axiom.imports" "$allow")"
      if [[ -n "$unexpected" ]]; then
        echo "FAIL axiom.exe [$t] imports symbols $allow does not permit:"
        printf '%s\n' "$unexpected" | sed 's/^/    /'
        status=1
      elif [[ -n "$(misplaced_imports "$w/axiom.exe" "$allow")" ]]; then
        # A POSIX-spelled Winsock name is permitted from ws2_32 and no
        # other DLL: this is where that `@dll` becomes a fact about the
        # executable (`scripts/lib/imports.sh`, `misplaced_imports`).
        echo "FAIL axiom.exe [$t] imports a permitted name from another DLL than $allow says:"
        misplaced_imports "$w/axiom.exe" "$allow" | sed 's/^/    /'
        status=1
      else
        echo "ok   axiom.exe [$t] links ($(wc -c < "$w/axiom.exe" | tr -d ' ') bytes) and imports only permitted names ($(grep -c . "$w/axiom.imports"), each from the DLL the list names)"
      fi
    done
    if [[ "$mode" == "--run" ]]; then
      w="$work/selfhost-$run_target"
      # Two levels below `stdlib/`, where the compiler looks for its
      # library when nothing names one.
      ax="$repo_root/.axiom-bin/axiom.exe"
      mkdir -p "$repo_root/.axiom-bin"
      cp "$w/axiom.exe" "$ax"
      unset AXIOM_STDLIB AXIOM_PATH

      # 2a. It emits itself as the host's compiler emitted it.
      if ( cd "$repo_root" && "$ax" --target="$run_target" emit-llvm core/main.ax -o "$w/native.ll" ) > "$w/native.log" 2>&1 \
         && cmp -s "$w/native.ll" "$sh/axiom-$run_target.ll"; then
        echo "ok   axiom.exe EXECUTED: its emission of core/main.ax is the host's, byte for byte ($(wc -l < "$w/native.ll" | tr -d ' ') lines)"
        { cat "$sh/axiom-$run_target.ll"; printf 'x'; } > "$w/axiom.ll.corrupt"
        if cmp -s "$w/native.ll" "$w/axiom.ll.corrupt"; then
          echo "FAIL negative probe [compiler]: a corrupted emission still matched"
          status=1
        else
          echo "ok   negative probe [compiler]: a corrupted emission does not match"
        fi
      else
        echo "FAIL axiom.exe did not emit core/main.ax as the host did"
        sed 's/^/    /' "$w/native.log" | head -5
        [[ -s "$w/native.ll" ]] && { diff "$sh/axiom-$run_target.ll" "$w/native.ll" || true; } | head -10 | sed 's/^/    /'
        status=1
      fi

      # 2b. Its driver builds hello: llc, a kernel32.lib it makes with
      #     llvm-dlltool, and lld-link.
      set +e
      ( cd "$repo_root" && "$ax" build tests/stdlib/010-hello.ax -o "$w/hello-native.exe" ) > "$w/build.log" 2>&1
      rc=$?
      [[ "$rc" -eq 0 ]] && "$w/hello-native.exe" > "$w/hello-native.stdout" 2>&1
      rc2=$?
      set -e
      if [[ "$rc" -ne 0 ]]; then
        echo "FAIL axiom.exe build of the hello case exited $rc"
        sed 's/^/    /' "$w/build.log" | head -5
        status=1
      elif [[ "$rc2" -ne 0 ]] || ! cmp -s "$w/hello-native.stdout" tests/stdlib/010-hello.out; then
        echo "FAIL the hello axiom.exe built exited $rc2, or its output is not the golden's"
        status=1
      else
        echo "ok   axiom.exe built the hello case, and it runs to the golden"
      fi

      # The clock, sleep, entropy, wait-words and memory, which the
      # platform module binds rather than a syscall. Each case prints its
      # own verdicts, and the golden is the one every POSIX target answers.
      for case in 306-monotonic-clock 309-entropy 851-instant-sleep 495-wait-word 650-net-tcp 308-poll-readiness 470-parallel 497-console-answers; do
        set +e
        ( cd "$repo_root" && gate_fixture_axc "$ax" build "tests/stdlib/$case.ax" -o "$w/$case.exe" ) > "$w/$case.build.log" 2>&1
        rc=$?
        [[ "$rc" -eq 0 ]] && "$w/$case.exe" > "$w/$case.stdout" 2> "$w/$case.stderr"
        rc2=$?
        set -e
        if [[ "$rc" -ne 0 ]]; then
          echo "FAIL axiom.exe build of $case exited $rc"
          sed 's/^/    /' "$w/$case.build.log" | head -5
          status=1
        elif [[ "$rc2" -ne 0 ]] || ! cmp -s "$w/$case.stdout" "tests/stdlib/$case.out"; then
          echo "FAIL $case on $run_target exited $rc2, or its output is not the golden's"
          { diff "tests/stdlib/$case.out" "$w/$case.stdout" || true; } | head -10 | sed 's/^/    /'
          sed 's/^/    /' "$w/$case.stderr" | head -3
          status=1
        else
          echo "ok   $case runs on $run_target to its golden"
        fi
      done

      # 3. The tree audit, built and run by this compiler, reports the
      #    fixture exactly as the emitting host did.
      tree_fixture "$w/tree"
      set +e
      ( cd "$repo_root" && "$ax" run examples/tree-audit/tree-audit.ax "$w/tree" ) > "$w/tree-audit.out" 2> "$w/tree-audit.err"
      rc=$?
      set -e
      if [[ "$rc" -eq 0 ]] && cmp -s "$w/tree-audit.out" "$sh/tree-audit.out"; then
        echo "ok   the tree audit's report on Windows is the emitting host's, byte for byte"
      else
        echo "FAIL the tree audit exited $rc, or its report differs from the emitting host's"
        { diff "$sh/tree-audit.out" "$w/tree-audit.out" || true; } | head -10 | sed 's/^/    /'
        sed 's/^/    /' "$w/tree-audit.err" | head -5
        status=1
      fi

      # 2c. Three failures, each contained by its recovery point, and
      #     a last test that still runs: exit 1 and the golden's report.
      set +e
      mixed="$( ( cd "$repo_root" && "$ax" test tests/testrunner/mixed-tests.ax ) 2>&1 )"
      rc=$?
      set -e
      if [[ "$rc" -eq 1 ]] && diff -u tests/testrunner/mixed-tests.out <(printf '%s\n' "$mixed") > "$w/mixed.diff"; then
        echo "ok   axiom.exe test reports tests/testrunner/mixed-tests.ax to its golden, exit 1"
      else
        echo "FAIL axiom.exe test on mixed-tests.ax exited $rc (want 1), or its report is not the golden"
        sed 's/^/    /' "$w/mixed.diff" | head -12
        status=1
      fi

      # 4. The standard-library battery, as `run-stdlib-tests.sh` runs it
      #    on the POSIX legs: every case in tests/stdlib built by this
      #    compiler and run to its golden, its exit status and, where a
      #    `.err` exists, its stderr, each up to the backtrace marker,
      #    with its `.in` on fd 0 or nothing. That script puts
      #    `pkg/axiom-oxide/axiom` on `AXIOM_PATH`, which is where `Ffi`
      #    lives. The entry is relative to the repository: `AXIOM_PATH`
      #    splits on `:`, and a Windows drive prefix contains one. Each
      #    build runs with the repository as its working directory.
      #    `tests/stdlib/windows-skip.txt` names the cases a target cannot
      #    run yet, for both targets or,
      #    with `@<target>` after the name, for one, each with its
      #    reason: a listed case that fails does not fail the leg and
      #    is reported with the first lines of its difference, a listed
      #    case that passes is reported so the list can shrink, and an
      #    unlisted case that fails fails the leg. A floor on the
      #    count that ran keeps an empty battery from passing.
      skip_list="$repo_root/tests/stdlib/windows-skip.txt"
      [[ -f "$skip_list" ]] || { echo "FAIL $skip_list is missing"; exit 1; }
      ran=0; skipped=0; passing_skips=""
      for case_file in "$repo_root"/tests/stdlib/[0-9]*.ax; do
        name="$(basename "$case_file" .ax)"
        # File cases must not share their working directory. Keep the
        # executable there too: 305-path-search baits an empty PATH
        # entry with the program's own name in the working directory.
        case_dir="$w/battery/$name"
        mkdir -p "$case_dir"
        listed=0
        grep -qE "^$name( |\$)|^$name@$run_target( |\$)" "$skip_list" && listed=1
        want_exit=0
        [[ -f "$repo_root/tests/stdlib/$name.exit" ]] && want_exit="$(tr -d '[:space:]' < "$repo_root/tests/stdlib/$name.exit")"
        stdin_src=/dev/null
        [[ -f "$repo_root/tests/stdlib/$name.in" ]] && stdin_src="$repo_root/tests/stdlib/$name.in"
        set +e
        ( cd "$repo_root" && AXIOM_PATH="pkg/axiom-oxide/axiom" timeout 300 python3 "$repo_root/scripts/lib/internal-probe.py" "$ax" --diagnostic-format=ai build "tests/stdlib/$name.ax" -o "$case_dir/$name.exe" ) > "$w/bat-$name.build.log" 2>&1
        brc=$?
        rrc=-1
        if [[ "$brc" -eq 0 ]]; then
          ( cd "$case_dir" && timeout 300 "./$name.exe" < "$stdin_src" > "$w/bat-$name.stdout" 2> "$w/bat-$name.stderr" )
          rrc=$?
        fi
        set -e
        good=0
        if [[ "$brc" -eq 0 && "$rrc" == "$want_exit" ]] \
           && cmp -s <(sed '/^axiom: backtrace/q' "$w/bat-$name.stdout") <(sed '/^axiom: backtrace/q' "$repo_root/tests/stdlib/$name.out"); then
          good=1
          if [[ -f "$repo_root/tests/stdlib/$name.err" ]] \
             && ! cmp -s <(sed '/^axiom: backtrace/q' "$w/bat-$name.stderr") <(sed '/^axiom: backtrace/q' "$repo_root/tests/stdlib/$name.err"); then
            good=0
          fi
        fi
        if [[ "$listed" -eq 1 ]]; then
          skipped=$((skipped + 1))
          if [[ "$good" -eq 1 ]]; then
            passing_skips="$passing_skips $name"
          else
            # a listed failure does not fail the leg, and says what it
            # did, so the reason beside its name can be checked
            echo "note $name is listed and still fails on $run_target: build exit $brc, run exit $rrc (want $want_exit)"
            { diff "$repo_root/tests/stdlib/$name.out" "$w/bat-$name.stdout" 2>/dev/null || true; } | head -4 | sed 's/^/    /'
            { cat "$w/bat-$name.build.log" "$w/bat-$name.stderr" 2>/dev/null || true; } | head -3 | sed 's/^/    /'
          fi
        elif [[ "$good" -eq 1 ]]; then
          ran=$((ran + 1))
        else
          echo "FAIL $name on $run_target: build exit $brc, run exit $rrc (want $want_exit), or its output is off the golden"
          { diff "$repo_root/tests/stdlib/$name.out" "$w/bat-$name.stdout" 2>/dev/null || true; } | head -6 | sed 's/^/    /'
          { cat "$w/bat-$name.build.log" "$w/bat-$name.stderr" 2>/dev/null || true; } | head -4 | sed 's/^/    /'
          status=1
        fi
        rm -f "$case_dir/$name.exe" "$case_dir/$name.obj"
      done
      if (( ran < 150 )); then
        echo "FAIL the battery ran only $ran case(s) to their goldens; the floor is 150"
        status=1
      else
        echo "ok   the battery: $ran case(s) ran on $run_target to their goldens, $skipped listed in tests/stdlib/windows-skip.txt"
      fi
      if [[ -n "$passing_skips" ]]; then
        echo "note listed case(s) that pass on $run_target and can leave the list:$passing_skips"
      fi
    else
      echo "ok   axiom.exe NOT EXECUTED: --link assembles, links and reads imports on a host that cannot run a PE; a Windows runner runs --run"
    fi
    exit "$status"
    ;;
  *) usage ;;
esac
