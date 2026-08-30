# Every place in the tree that states the version, with the pattern that
# reads it AND the rewrite that moves it.
#
# WHY THIS FILE EXISTS. `check-version.sh` already knew every site and
# how to read each one - that is the hard half, and it was the only half
# automated. Bumping was one hand edit per site across four file
# formats, which is exactly the shape that produces a release where two
# of them are missed and the gate catches it after the tag is cut.
#
# THE COUNT IS NOT WRITTEN DOWN HERE, deliberately. `VERSION_SITES`
# below IS the count, `check-version.sh` prints the totals it derives
# from this table on every run, and a number restated in prose beside a
# list is a second copy of the list with no gate on it - which is the
# failure this file exists to prevent, one level up. It was already
# wrong when this paragraph said seventeen.
#
# The list lives HERE, once, and both the gate and `bump-version.sh`
# source it. A copy in the bump script would be a second list to keep in
# step with the first, and the failure mode of that is silent: the bump
# rewrites sixteen sites, the gate checks seventeen, and the number they
# disagree about is the one nobody edited.
#
# EVERY EXTRACTOR HAS A REPLACER WITH THE SAME SHAPE. They are written as
# a pair on purpose: a replacer whose pattern is looser than its
# extractor's rewrites text the gate is not looking at, and one that is
# tighter leaves a site behind. Keep the two in step, and when you add a
# site add both halves.

# --- readers: print every version the file states, one per line -------
ax_version()   { grep -oE 'Axiom [0-9]+\.[0-9]+\.[0-9]+ (\(build|- REPL)' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
axv_version()  { grep -oE '\(pub fn \(axiomVersion\) "[0-9]+\.[0-9]+\.[0-9]+"\)' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
lsp_version()  { grep -oE '"version" \(jsonStr "[0-9]+\.[0-9]+\.[0-9]+"\)' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
toml_version() { grep -oE '^version = "[0-9]+\.[0-9]+\.[0-9]+"|version = "[0-9]+\.[0-9]+\.[0-9]+" }' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
json_version() { grep -oE '"version": "[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
# The language server's `serverInfo` as it appears in a CHECKED-IN LSP
# transcript: no space after the colon, unlike the manifests above.
lspg_version() { grep -oE '"version":"[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
# `SECURITY.md`'s supported-release line. A security policy naming a
# version nothing holds to `VERSION` is a policy that goes stale
# silently, which is the one failure mode a security document cannot
# afford - so the sentence is a site like any other.
sec_version()  { grep -oE 'The supported release is \*\*[0-9]+\.[0-9]+\.[0-9]+\*\*' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }

# A `Cargo.lock`'s entry for a workspace member, which is a site's
# OUTPUT the way `tree-sitter-axiom/src/parser.c` is: cargo derives it
# from `rust/Cargo.toml`, and a bump that moves the manifest and not the
# lock leaves the two disagreeing until the next `cargo build` quietly
# fixes it. 0.3.1 shipped with both lockfiles still reading 0.3.0, and
# what found it was a gate battery running `cargo test` - not a check.
#
# TWO PACKAGES ARE EXCLUDED BY NAME. `axiom-leaky` and `axiom-nostd` are
# example crates carrying their own `0.1.0`, deliberately, and naming
# them here is what makes that choice visible - the same argument
# `check-stdlib-api.sh` gives for naming its module list rather than
# globbing it. A third-party package's version is never read: the awk
# only prints a version that FOLLOWS an `axiom-` name line.
lock_version()  {
  awk '/^name = "axiom-/ { n = $3; gsub(/"/, "", n); next }
       /^version = "/ {
         if (n != "" && n != "axiom-leaky" && n != "axiom-nostd") {
           v = $3; gsub(/"/, "", v); print v
         }
         n = ""
       }'
}

# --- writers: rewrite this file's versions to $2 ----------------------
#
# `sed` to a temp file and move it, rather than `-i`: BSD `sed` needs an
# argument to `-i` and GNU `sed` refuses one, and this repository's gates
# run on both.
_rewrite() { # _rewrite <file> <sed-expr>
  local f="$1" e="$2" t
  t="$(mktemp)"
  sed -E "$e" "$f" > "$t" && cat "$t" > "$f"
  rm -f "$t"
}

ax_replace()   { _rewrite "$1" "s/(Axiom )[0-9]+\.[0-9]+\.[0-9]+( (\(build|- REPL))/\1$2\2/g"; }
axv_replace()  { _rewrite "$1" "s/(\(pub fn \(axiomVersion\) \")[0-9]+\.[0-9]+\.[0-9]+(\"\))/\1$2\2/g"; }
lsp_replace()  { _rewrite "$1" "s/(\"version\" \(jsonStr \")[0-9]+\.[0-9]+\.[0-9]+(\"\))/\1$2\2/g"; }
json_replace() { _rewrite "$1" "s/(\"version\": \")[0-9]+\.[0-9]+\.[0-9]+(\")/\1$2\2/g"; }
lspg_replace() { _rewrite "$1" "s/(\"version\":\")[0-9]+\.[0-9]+\.[0-9]+(\")/\1$2\2/g"; }
sec_replace()  { _rewrite "$1" "s/(The supported release is \*\*)[0-9]+\.[0-9]+\.[0-9]+(\*\*)/\1$2\2/g"; }
# The matching writer: rewrite exactly the versions `lock_version`
# reads, and nothing else in the file.
lock_replace() {
  local t; t="$(mktemp)"
  awk -v ver="$2" '
    /^name = "axiom-/ { n = $3; gsub(/"/, "", n); print; next }
    /^version = "/ {
      if (n != "" && n != "axiom-leaky" && n != "axiom-nostd") {
        print "version = \"" ver "\""; n = ""; next
      }
      n = ""
    }
    { print }
  ' "$1" > "$t" && cat "$t" > "$1"
  rm -f "$t"
}
# Both `toml_version` shapes in one pass: a line-anchored key, and the
# inline `version = "X" }` a workspace dependency uses.
toml_replace() {
  _rewrite "$1" "s/^(version = \")[0-9]+\.[0-9]+\.[0-9]+(\")/\1$2\2/g"
  _rewrite "$1" "s/(version = \")[0-9]+\.[0-9]+\.[0-9]+(\" \})/\1$2\2/g"
}

# <file>|<expected-count>|<reader>|<writer>
#
# THE LSP GOLDENS ARE SITES. Each pins the server's `serverInfo.version`,
# so every release moved eight checked-in transcripts by hand.
# `check-driver.sh` already cross-checks those goldens against the built
# binary and caught the miss when 0.3.0 was cut - which is the gate
# working, and also eight files the bump did not know about. Listing
# them here is what makes the bump and the check agree about them.
#
# The count is a COUNT and not a floor, and `check-version.sh`'s header
# records why: `rust/Cargo.toml` could shrink from four version keys to
# one and still pass a floor, because the survivor agrees and the three
# that stopped matching are invisible to a test that only asks whether
# the file said the number at all.
VERSION_SITES="
self_host/build.ax|1|axv_version|axv_replace
self_host/lsp.ax|1|lsp_version|lsp_replace
rust/Cargo.toml|4|toml_version|toml_replace
rust/Cargo.lock|7|lock_version|lock_replace
rust/examples/nostd/Cargo.lock|4|lock_version|lock_replace
tree-sitter-axiom/package.json|1|json_version|json_replace
tree-sitter-axiom/tree-sitter.json|1|json_version|json_replace
README.md|2|ax_version|ax_replace
docs/reference.md|1|ax_version|ax_replace
SECURITY.md|1|sec_version|sec_replace
tests/lsp/010-clean.golden|1|lspg_version|lspg_replace
tests/lsp/020-undefined.golden|1|lspg_version|lspg_replace
tests/lsp/030-utf16-columns.golden|1|lspg_version|lspg_replace
tests/lsp/040-missing-import.golden|1|lspg_version|lspg_replace
tests/lsp/050-unparseable.golden|1|lspg_version|lspg_replace
tests/lsp/060-outline.golden|1|lspg_version|lspg_replace
tests/lsp/070-warning-only.golden|1|lspg_version|lspg_replace
tests/lsp/080-many-diagnostics.golden|1|lspg_version|lspg_replace
"
