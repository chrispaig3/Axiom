# Every place in the tree that states the version, with the reader that
# extracts it and the writer that rewrites it.
#
# `check-version.sh` and `bump-version.sh` both source this file, so the
# check and the bump share one list. A second copy would drift silently:
# the bump would rewrite one set of sites and the gate would check another.
#
# The number of sites isn't written here. `VERSION_SITES` is the count,
# and `check-version.sh` prints the totals on every run. A number in prose
# would be a copy of the list with no gate on it.
#
# Every reader has a writer with the same pattern. A looser writer
# rewrites text the gate isn't reading, and a tighter one leaves a site
# behind. When you add a site, add both halves.

# --- readers: print every version the file states, one per line -------
ax_version()   { grep -oE 'Axiom [0-9]+\.[0-9]+\.[0-9]+ (\(build|- REPL)' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
axv_version()  { grep -A1 -F '(pub fn (axiomVersion)' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
# No `-o` on the first grep: GNU grep drops `-A` context under `-o` and
# BSD keeps it, so the next-line version would vanish on Linux.
# `-A1 -F` behaves the same on both.
lsp_version()  { grep -oE '"version" \(jsonStr "[0-9]+\.[0-9]+\.[0-9]+"\)' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
toml_version() { grep -oE '^version = "[0-9]+\.[0-9]+\.[0-9]+"|version = "[0-9]+\.[0-9]+\.[0-9]+" }' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
json_version() { grep -oE '"version": "[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
# The language server's `serverInfo` as it appears in a checked-in LSP
# transcript: no space after the colon, unlike the manifests above.
lspg_version() { grep -oE '"version":"[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
# `SECURITY.md`'s supported-release line. A security policy must not go
# stale silently, so the sentence is a site like any other.
sec_version()  { grep -oE 'The supported release is \*\*[0-9]+\.[0-9]+\.[0-9]+\*\*' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }

# A `Cargo.lock` entry for a workspace member. Cargo derives it from
# `rust/Cargo.toml`, but a bump that moves the manifest and not the lock
# leaves the two disagreeing until the next `cargo build`.
#
# `axiom-leaky` and `axiom-nostd` are example crates with their own
# `0.1.0`, so they are excluded by name, which keeps that choice visible.
# Third-party versions are never read: the awk prints only a version that
# follows an `axiom-` name line.
lock_version()  {
  awk '/^name = "axiom-/ { n = $3; gsub(/"/, "", n); next }
       /^version = "/ {
         if (n != "" && n != "axiom-leaky" && n != "axiom-nostd") {
           v = $3; gsub(/"/, "", v); print v
         }
         n = ""
       }'
}

# `web/src/data/site.ts` holds the version the page shows as its kicker.
# `web/scripts/check-claims.mjs` guards the counts derived from the tree,
# but not this number, so it is a site here.
web_version()  { grep -oE "'[0-9]+[.][0-9]+[.][0-9]+'" | grep -oE '[0-9]+[.][0-9]+[.][0-9]+'; }

# --- writers: rewrite this file's versions to $2 ----------------------
#
# `sed` to a temp file and copy it back, rather than `-i`: BSD `sed`
# needs an argument to `-i`, GNU `sed` refuses one, and the gates run on
# both.
_rewrite() { # _rewrite <file> <sed-expr>
  local f="$1" e="$2" t
  t="$(mktemp)"
  sed -E "$e" "$f" > "$t" && cat "$t" > "$f"
  rm -f "$t"
}

ax_replace()   { _rewrite "$1" "s/(Axiom )[0-9]+\.[0-9]+\.[0-9]+( (\(build|- REPL))/\1$2\2/g"; }
axv_replace()  { _rewrite "$1" "/\(pub fn \(axiomVersion\)/{N;s/\"[0-9]+\.[0-9]+\.[0-9]+\"/\"$2\"/;}"; }
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

# `web/package-lock.json` states the site's own version twice, at the top
# level and in the `""` entry under `packages`, then a `"version"` for
# every locked dependency. `json_version` would read them all, so this
# anchors on the site's name and takes only the version that follows it,
# as `lock_version` does.
#
# `npm install` rewrites the lock from `web/package.json`, but it is
# listed beside the manifest so that a bump can't leave it behind.
npmlock_version() {
  awk '/"name": "axiom-site"/ { n = 1; next }
       n && /"version": "/ {
         if (match($0, /[0-9]+\.[0-9]+\.[0-9]+/)) {
           print substr($0, RSTART, RLENGTH); n = 0
         }
       }'
}
# The matching writer: rewrite exactly the two versions
# `npmlock_version` reads, and no dependency's.
npmlock_replace() {
  local t; t="$(mktemp)"
  awk -v ver="$2" '
    /"name": "axiom-site"/ { n = 1; print; next }
    n && /"version": "[0-9]+\.[0-9]+\.[0-9]+"/ {
      sub(/"version": "[0-9]+\.[0-9]+\.[0-9]+"/, "\"version\": \"" ver "\"")
      n = 0
    }
    { print }
  ' "$1" > "$t" && cat "$t" > "$1"
  rm -f "$t"
}

# `web/src/data/bench.ts` names the compiler inside the row label, as
# `'Axiom X.Y.Z'`, so the quote isn't next to the digits and `web_version`
# can't see it. This reader anchors on the word instead. A row labelled
# with the wrong compiler claims a measurement nobody ran.
webbench_version() { grep -oE "Axiom [0-9]+[.][0-9]+[.][0-9]+" | grep -oE '[0-9]+[.][0-9]+[.][0-9]+'; }

web_replace()  { _rewrite "$1" "s/'[0-9]+[.][0-9]+[.][0-9]+'/'$2'/g"; }
webbench_replace() { _rewrite "$1" "s/(Axiom )[0-9]+[.][0-9]+[.][0-9]+/\\1$2/g"; }

# <file>|<expected-count>|<reader>|<writer>
#
# Each count is exact, not a floor; `check-version.sh`'s header says why.
# README's Quick start carries the REPL greeting, `docs/status.md` the
# `axiom version` banner and `docs/reference.md` a REPL session. Each is
# counted, because the bump leaves an uncounted copy at the old number.
#
# The LSP goldens pin the server's `serverInfo.version`. `check-driver.sh`
# cross-checks them against the built binary, and listing them here lets
# the bump move them too.
#
# Comments can't go inside the string below: it is a plain variable, not a
# heredoc, and a `#` line in it is parsed as a site.
VERSION_SITES="
web/src/data/site.ts|1|web_version|web_replace
web/src/data/bench.ts|1|webbench_version|webbench_replace
web/package.json|1|json_version|json_replace
web/package-lock.json|2|npmlock_version|npmlock_replace
self_host/build.ax|1|axv_version|axv_replace
self_host/lsp.ax|1|lsp_version|lsp_replace
rust/Cargo.toml|4|toml_version|toml_replace
rust/Cargo.lock|7|lock_version|lock_replace
rust/examples/nostd/Cargo.lock|4|lock_version|lock_replace
tree-sitter-axiom/package.json|1|json_version|json_replace
tree-sitter-axiom/tree-sitter.json|1|json_version|json_replace
README.md|1|ax_version|ax_replace
docs/status.md|1|ax_version|ax_replace
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
tests/lsp/090-related-spans.golden|1|lspg_version|lspg_replace
tests/lsp/100-lint-dead-branch.golden|1|lspg_version|lspg_replace
tests/lsp/101-lint-bool-if.golden|1|lspg_version|lspg_replace
tests/lsp/102-lint-unused-let.golden|1|lspg_version|lspg_replace
tests/lsp/103-lint-nolint.golden|1|lspg_version|lspg_replace
"
