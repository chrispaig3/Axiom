#!/usr/bin/env bash
# `docs/stdlib-api.md` is generated, and this is what keeps it true.
#
# WHY A REFERENCE AT ALL. The standard library's public surface was
# described in two hand-written tables - one in `README.md`, one in
# `docs/reference.md` - which between them named a minority of the
# public names and had already drifted: `docs/reference.md` called the
# `Err` macro `try` where the library spells it `try!`. Nothing read
# either table. A per-symbol reference typed by hand would drift the
# same way and faster, so this one is derived from the source and
# diffed on every run.
#
# WHAT GENERATES IT. `examples/axdoc/axdoc.ax`, an Axiom program, which
# is also this repository's worked example of a real program: it reads
# files, splits and slices strings, walks a `Vec` of lines, joins two
# sources of truth and writes a document. That it is the example and
# the tool at once is deliberate - an example nothing depends on rots
# as quietly as a hand-written table.
#
# THE TWO SOURCES, AND WHY NEITHER ALONE. Visibility is only in the
# SOURCE: `axiom symbols` has no `pub` field and emits no row for a
# macro, so an AXSYM-driven reference would print an `IO` with no
# `println` and be self-consistent about it. The EFFECT ROW is only in
# AXSYM: it is the compiler's fixpoint over every body, and it is the
# column an Axiom reference exists for.
#
# THE ASSERTIONS, in the order they depend on each other:
#
#   1. Regenerating equals the committed document, byte for byte.
#   2. Every `(pub` name in `stdlib/` appears in it EXACTLY ONCE -
#      checked against a list `grep` derives from the sources, which is
#      a second source. A generator that dropped a module would pass 1
#      by being re-blessed and fails here.
#   3. The five `Sys/Platform.*.ax` files declare the same public
#      names. The document carries one of them, so this is what makes
#      that safe rather than darwin-flavoured - and it is what holds
#      the Windows module, which is functions over kernel32 rather
#      than a table of numbers, to the same public surface.
#   4. A documentation-coverage floor, so a new public name with no
#      comment above it is visible rather than a blank cell nobody
#      counts.
#   5. NEGATIVE PROBE: a public name added to a copy of the library
#      must change the generated document. A generator that emitted a
#      constant would pass 1, 3 and 4.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

doc="docs/stdlib-api.md"
gen="examples/axdoc/axdoc.ax"
failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# The modules the reference covers, in the order it prints them. Named
# rather than globbed: `Sys/Platform` has one file per target declaring
# the same names, so a glob would print it several times, and the choice
# of which one to carry is a decision this list makes visible.
modules="
stdlib/Agent/Tags.ax
stdlib/Err.ax
stdlib/Fallible.ax
stdlib/Ffi.ax
stdlib/Fmt.ax
stdlib/Html.ax
stdlib/Http.ax
stdlib/IO.ax
stdlib/Intern.ax
stdlib/Job.ax
stdlib/Json.ax
stdlib/Map.ax
stdlib/Mem.ax
stdlib/Path.ax
stdlib/Pre.ax
stdlib/Rpc.ax
stdlib/Show.ax
stdlib/Str.ax
stdlib/Sys.ax
stdlib/Sys/Platform.darwin.ax
stdlib/Test.ax
stdlib/Tui/Edit.ax
stdlib/Tui/Keys.ax
stdlib/Tui/Term.ax
stdlib/Utf8.ax
stdlib/Vec.ax
"
mod_list="$(printf '%s' "$modules" | grep -v '^$')"

# Every module named here must be in the tree, and every stdlib module
# except the three other `Platform` files must be named here. Both
# directions, because a list that is checked in one direction rots in
# the other - which is the lesson `gate_prose_docs` carries.
checks=$((checks + 1))
listed_missing=""
while IFS= read -r m; do
  [[ -f "$repo_root/$m" ]] || listed_missing="$listed_missing $m"
done <<< "$mod_list"
tree_unlisted=""
while IFS= read -r m; do
  case "$m" in
      stdlib/Sys/Platform.linux-*|stdlib/Sys/Platform.freebsd.ax|stdlib/Sys/Platform.windows.ax) continue ;;
  esac
  printf '%s\n' "$mod_list" | grep -qx "$m" || tree_unlisted="$tree_unlisted $m"
done < <(cd "$repo_root" && find stdlib -name '*.ax' -type f | LC_ALL=C sort)
if [[ -z "$listed_missing$tree_unlisted" ]]; then
  ok "the module list and stdlib/ agree, $(printf '%s\n' "$mod_list" | grep -c .) modules"
else
  bad "the module list has drifted"
  [[ -n "$listed_missing" ]] && echo "     named here, not in the tree:$listed_missing"
  [[ -n "$tree_unlisted" ]]  && echo "     in the tree, not named here:$tree_unlisted"
fi

# --------------------------------------------------------------------
# The AXSYM stream the generator joins against.
# --------------------------------------------------------------------
# One `symbols` run per module, concatenated. `symbols` resolves
# imports, so each run also prints the modules that one imports; the
# generator's lookup takes the first row for a name and every name in
# this library is unique, which the next check establishes rather than
# assumes.
build_axsym() {
  local out="$1" m
  : > "$out"
  while IFS= read -r m; do
    "$axc" --diagnostic-format=ai symbols "$m" >> "$out" 2>/dev/null || true
  done <<< "$mod_list"
}

# The generator is BUILT ONCE and then run as a binary, rather than run
# through `axiom run` each time. Not for speed: `run` writes its scratch
# executable and intermediates into the WORKING DIRECTORY, and the
# working directory here has to be the tree root, because the module
# paths the document prints are repo-relative and the generator is
# handed them as it will print them. A gate that writes into the
# repository is a gate that can leave something in it.
gen_bin="$work/axdoc"
if ! AXIOM_STDLIB="$repo_root/stdlib" "$axc" build \
       --input "$repo_root/$gen" --output "$gen_bin" >"$work/gen.log" 2>&1; then
  echo "FAIL: could not build $gen"
  sed 's/^/     /' "$work/gen.log" | head -20
  exit 1
fi

generate() {  # <src-root> <out-file>
  local root="$1" out="$2" axsym="$work/axsym.$$"
  ( cd "$root" && build_axsym "$axsym" )
  # shellcheck disable=SC2046
  ( cd "$root" && AXIOM_STDLIB="$root/stdlib" "$gen_bin" "$axsym" $(printf '%s ' $mod_list) ) > "$out"
}

# --------------------------------------------------------------------
echo "== regenerating the reference =="
# --------------------------------------------------------------------
generate "$repo_root" "$work/fresh.md"
if [[ ! -s "$work/fresh.md" ]]; then
  bad "the generator produced nothing"
elif [[ ! -f "$repo_root/$doc" ]]; then
  bad "$doc is missing - run this gate with AXIOM_BLESS=1 to write it"
elif diff -u "$repo_root/$doc" "$work/fresh.md" > "$work/doc.diff"; then
  ok "$doc is what the generator writes ($(wc -l <"$work/fresh.md" | tr -d ' ') lines)"
else
  bad "$doc differs from a fresh generation"
  head -40 "$work/doc.diff" | sed 's/^/     /'
  echo "     Re-generate with: AXIOM_BLESS=1 scripts/check-stdlib-api.sh"
fi
if [[ "${AXIOM_BLESS:-0}" == 1 ]]; then
  cp "$work/fresh.md" "$repo_root/$doc"
  echo "blessed $doc"
  failed=0
fi

# --------------------------------------------------------------------
echo
echo "== every public name appears exactly once =="
# --------------------------------------------------------------------
# The list comes from `grep` over the sources, not from the generator,
# so this cannot pass by the generator and the document agreeing with
# each other about a name neither has.
names="$work/names"
while IFS= read -r m; do
  sed -nE 's/^\(pub (:: |macro |data |struct |trait |type )\(?([A-Za-z0-9_!?*+/<>=-]+).*/\2/p' "$repo_root/$m"
  sed -nE 's/^\(effect ([A-Za-z0-9_]+).*/\1/p' "$repo_root/$m"
done <<< "$mod_list" | LC_ALL=C sort -u > "$names"
n_names="$(grep -c . "$names" || true)"
missing=0; dup=0
while IFS= read -r nm; do
  [[ -z "$nm" ]] && continue
  c="$(grep -c "^| \`$(printf '%s' "$nm" | sed 's/[][\.*^$/]/\\&/g')\` |" "$repo_root/$doc" || true)"
  if   (( c == 0 )); then missing=$((missing + 1)); [[ $missing -le 5 ]] && echo "     absent: $nm"
  elif (( c > 1 )); then dup=$((dup + 1));         [[ $dup -le 5 ]] && echo "     $c times: $nm"
  fi
done < "$names"
if (( missing == 0 && dup == 0 )); then
  ok "all $n_names public names appear exactly once"
else
  bad "$missing public name(s) absent from $doc, $dup duplicated"
fi
# A population floor, so a `sed` that stops matching reads as red
# rather than as a library with nothing in it. Re-derive it, with the
# date and the command, when it legitimately moves.
#   2026-08-25: 417, from the sed above over the 20 modules listed here.
if (( n_names >= 400 )); then
  ok "the name sweep found $n_names names (floor 400, measured 417 on 2026-08-25)"
else
  bad "the name sweep found only $n_names names - the pattern has stopped matching"
fi

# --------------------------------------------------------------------
echo
echo "== the four Sys/Platform files declare the same names =="
# --------------------------------------------------------------------
# The reference carries the darwin one. That is only safe while the
# the platform files agree, and nothing else in the tree checks that they do. The
# Windows one binds kernel32 in a NON-pub `extern` block and exports
# the same names as the others; a `pub` on that block would widen its
# surface and fail here, which is the point.
plat_names() { sed -nE 's/^\(pub (:: |macro |data |struct |trait |type )\(?([A-Za-z0-9_!?*+/<>=-]+).*/\2/p' "$1" | LC_ALL=C sort; }
plat_ok=1
plat_names "$repo_root/stdlib/Sys/Platform.darwin.ax" > "$work/plat.darwin"
  for other in linux-aarch64 linux-x86_64 freebsd windows; do
  plat_names "$repo_root/stdlib/Sys/Platform.$other.ax" > "$work/plat.$other"
  if ! diff -q "$work/plat.darwin" "$work/plat.$other" >/dev/null; then
    bad "Sys/Platform.darwin.ax and Sys/Platform.$other.ax declare different names"
    { diff "$work/plat.darwin" "$work/plat.$other" || true; } | head -10 | sed 's/^/     /'
    plat_ok=0
  fi
done
(( plat_ok )) && ok "all five Platform files declare the same $(grep -c . "$work/plat.darwin") names"

# --------------------------------------------------------------------
echo
echo "== documentation coverage =="
# --------------------------------------------------------------------
# A blank Summary cell is a public name with no comment block above it.
# The count is reported and floored, so adding an undocumented name is
# visible in the diff rather than invisible in a table.
# A RATCHET, and it is set AT the measured value rather than below it,
# because the thing it guards is a habit and not a number: a public
# name added with no comment block above it drops this by one and must
# be a conversation. Removing a documented name legitimately lowers it
# too, and lowering it is then a deliberate edit with the new count and
# the date written here - which is what "re-derive rather than relax"
# means. Measured 2026-08-25: 290 of 417.
rows="$(grep -c '^| `' "$repo_root/$doc" || true)"
blank="$(grep -c '^| `.*| *|$' "$repo_root/$doc" || true)"
documented=$((rows - blank))
echo "     $documented of $rows rows carry a summary"
if (( documented >= 290 )); then
  ok "documentation coverage is $documented of $rows (ratchet 290, set 2026-08-25)"
else
  bad "documentation coverage fell to $documented, below the ratchet of 290"
  echo "     A public name with no comment block above it is a blank Summary"
  echo "     cell. Document it, or lower this number here with the date and"
  echo "     the accounting for why it moved."
fi

# --------------------------------------------------------------------
echo
echo "== negative probe: a new public name must change the document =="
# --------------------------------------------------------------------
probe="$work/probe"
mkdir -p "$probe"
cp -R "$repo_root/stdlib" "$probe/stdlib"
cat >> "$probe/stdlib/Path.ax" <<'PROBE'

; A probe declaration, added by scripts/check-stdlib-api.sh.
(pub :: pathProbeForTheGate (-> String String))

(pub fn (pathProbeForTheGate p) p)
PROBE
generate "$probe" "$work/probe.md" 2>/dev/null || true
if [[ ! -s "$work/probe.md" ]]; then
  bad "the probe generated nothing - it would agree with anything"
elif grep -q 'pathProbeForTheGate' "$work/probe.md"; then
  ok "a public name added to a copy appears in the regenerated reference"
else
  bad "a public name added to a copy did NOT appear - the generator is not reading the source"
fi
if cmp -s "$work/probe.md" "$work/fresh.md"; then
  bad "the probe's document is identical to the real one"
else
  ok "and the document differs from the one above it"
fi

echo
if (( failed > 0 )); then
  echo "check-stdlib-api: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-stdlib-api: $checks checks - $doc is what the library says it is,"
echo "                  and a name added to the library appears in it"
