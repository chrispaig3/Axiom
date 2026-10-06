# ---------------------------------------------------------------------
# Reads what an executable imports, in any of the three object formats,
# and holds a Windows import list to the reviewed allowlist.
#
# `check-freestanding.sh`, `check-windows-hello.sh` and the other gates
# that source this share one reader, so their negative probes exercise
# the same pipeline as their real checks.
#
# The object's own magic picks the format, never the host: a Windows
# `.exe` is cross-linked on macOS and Linux before any Windows runner
# sees it. A file this can't read is refused, since an empty answer
# looks like a pass.
#
# Each format gets the one edit its convention needs. GNU `nm -D
# --undefined-only` prints `malloc@GLIBC_2.2.5`, and callers match
# anchored names (`^($libc_names)$`), so `sed 's/@.*//'` is what lets
# the freestanding check fail on Linux. Mach-O names lose their leading
# underscore instead. `nm` lists no useful imports for a PE, so a PE is
# read with `llvm-readobj --coff-imports`, whose `Symbol:` lines are the
# names the loader resolves, per DLL.
# ---------------------------------------------------------------------

# The object's format from its magic: `pe`, `elf` or `macho` on stdout,
# or a refusal and status 1 for anything else. Any gate that needs a
# per-format answer calls this rather than reading the magic itself.
# `od` renders the bytes as hex because the ELF magic starts with DEL
# (`\x7f`), which a text match such as `ELF*` misses.
object_format() {
  local magic
  magic="$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')"
  case "$magic" in
    4d5a*)    echo pe ;;
    7f454c46) echo elf ;;
    cffaedfe|feedfacf|cefaedfe|feedface|cafebabe|bebafeca)
              echo macho ;;
    *)        echo "object_format: $1 is not a PE, ELF or Mach-O object (magic $magic)" >&2; return 1 ;;
  esac
}

imports_of() {
  local fmt
  fmt="$(object_format "$1")" || return 1
  case "$fmt" in
    pe)    llvm-readobj --coff-imports "$1" 2>/dev/null | awk '/^ *Symbol: / {print $2}' | LC_ALL=C sort -u || true ;;
    elf)   nm -D --undefined-only "$1" 2>/dev/null | awk '{print $NF}' | sed 's/@.*//' || true ;;
    macho) nm -u "$1" 2>/dev/null | sed 's/^_//' || true ;;
  esac
}

# The Windows import allowlist, `scripts/platform-allow.windows.txt`, as
# names: comments and blanks dropped, sorted in C collation for `comm`.
# `|| true` because a list of only comments makes `grep` exit 1, which
# under `set -e` ends the gate before its verdict.
permitted_windows() {
  grep -vE '^\s*(#|$)' "$1" | sed 's/#.*//' | tr -d ' \t' | grep . | LC_ALL=C sort -u || true
}

# The names in `<imports>` (a file, one per line) that `<allow-file>`
# does not permit. Nothing on success.
unpermitted_imports() {
  LC_ALL=C comm -23 <(LC_ALL=C sort -u "$1") <(permitted_windows "$2")
}

# Every symbol an IR module declares: its import surface before it is
# linked, `dllimport` or not.
declares_of() {
  grep -oE '^declare [^@]*@[A-Za-z_][A-Za-z0-9_$.]*\(' "$1" | sed -E 's/^declare [^@]*@//; s/\($//' | LC_ALL=C sort -u || true
}
