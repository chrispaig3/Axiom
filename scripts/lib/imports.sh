# ---------------------------------------------------------------------
# Reading what an executable imports, on any of the three object
# formats, and holding a Windows import list to the reviewed allowlist.
#
# ONE COPY. `check-freestanding.sh` sweeps every stdlib case through
# `imports_of` and runs its negative probes through the same function;
# the Windows hello gate (`check-windows-hello.sh`) reads a `.exe`
# linked on a Windows runner through it too. A probe against a second
# copy of a pipeline proves the copy works and nothing else, which is
# why the reader moved here the day a third script needed it.
#
# THE FILE DECIDES, NOT THE HOST. `imports_of` dispatched on `uname -s`
# until 2026-08-29, which was two arms for two hosts; a PE is a third
# format and it is read on EVERY host, because a Windows executable is
# linked on macOS and Linux (cross) before any Windows runner sees one.
# So the arm is chosen by the object's own magic - `MZ`, `\x7fELF`, or
# one of Mach-O's - and a file this cannot read is a loud refusal, since
# an empty answer is what a vacuous pass looks like.
#
# `sed 's/@.*//'` IS THE ELF HALF OF THE COMPARISON, and without it the
# freestanding check could not fail on Linux. GNU `nm -D
# --undefined-only` prints a versioned import as `malloc@GLIBC_2.2.5`,
# and the test is anchored - `grep -qE "^($libc_names)$"` - so `malloc`
# never matched `malloc@GLIBC_2.2.5` and a program that really did
# import libc passed. Mach-O has no version suffix and needs its leading
# underscore stripped instead; each format gets the one edit its own
# convention requires, which is the lesson `check-backtrace.sh` records
# after applying Mach-O's to ELF. The PE arm reads the import directory
# with `llvm-readobj --coff-imports`: `nm` on a PE lists no imports
# usefully, and the `Symbol:` lines under each `Import {` block are the
# names the loader will resolve, per DLL.
# ---------------------------------------------------------------------
imports_of() {
  local magic
  magic="$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')"
  case "$magic" in
    4d5a*)    llvm-readobj --coff-imports "$1" 2>/dev/null | awk '/^ *Symbol: / {print $2}' | LC_ALL=C sort -u || true ;;
    7f454c46) nm -D --undefined-only "$1" 2>/dev/null | awk '{print $NF}' | sed 's/@.*//' || true ;;
    cffaedfe|feedfacf|cefaedfe|feedface|cafebabe|bebafeca)
              nm -u "$1" 2>/dev/null | sed 's/^_//' || true ;;
    *)        echo "imports_of: $1 is not a PE, ELF or Mach-O object (magic $magic)" >&2; return 1 ;;
  esac
}

# The Windows import allowlist - `scripts/platform-allow.windows.txt` -
# as names: comments and blanks dropped, in C collation for `comm`.
# `|| true` for the reason check-ffi.sh gives at its own manifest read:
# a list of nothing but comments makes `grep` exit 1, and under `set -e`
# that is the gate vanishing before its own verdict.
permitted_windows() {
  grep -vE '^\s*(#|$)' "$1" | sed 's/#.*//' | tr -d ' \t' | grep . | LC_ALL=C sort -u || true
}

# The names in `<imports>` (a file, one per line) that `<allow-file>`
# does not permit. Nothing on success.
unpermitted_imports() {
  LC_ALL=C comm -23 <(LC_ALL=C sort -u "$1") <(permitted_windows "$2")
}

# Every symbol an IR module declares - its import surface before it is
# linked, `dllimport` or not.
declares_of() {
  grep -oE '^declare [^@]*@[A-Za-z_][A-Za-z0-9_$.]*\(' "$1" | sed -E 's/^declare [^@]*@//; s/\($//' | LC_ALL=C sort -u || true
}
