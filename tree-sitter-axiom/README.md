# tree-sitter-axiom

Tree-sitter grammar for Axiom, for editor support: syntax highlighting,
structural selection, and incremental reparsing.

```
tree-sitter-axiom/
├── grammar.js               the grammar
├── src/scanner.c            the external scanner: nesting `#| ... |#`
├── src/parser.c             generated from grammar.js, committed
├── queries/highlights.scm   highlighting captures
├── queries/rainbows.scm     bracket pairs by nesting depth (Helix `rainbow-brackets`, rainbow-delimiters.nvim)
├── test/corpus/             tree-shape tests
└── tree-sitter.json         CLI configuration
```

## Verifying it

```bash
./scripts/check-tree-sitter.sh
```

Four steps, and the third is the one that matters most.

1. Every Axiom code block in the swept documents balances its
   delimiters. This runs first because it needs neither the tree-sitter
   CLI nor a compiler, so a machine that has neither still gets it. It
   is here rather than in a gate of its own because it belongs to the
   same CI job: the cheap one that needs no compiler.
2. `tree-sitter test` runs the corpus in `test/corpus/`, pinning the
   tree *shape* per construct. A change that still parses everything but
   reorganises the tree breaks every query silently; this catches it.
3. Every `.ax` file in the repository is parsed and must produce no
   `ERROR` node — the whole repository, not a list: the corpus is
   written by whoever changed the grammar, and the standard library and
   the compiler's own sources are not. When the language grows a form,
   `stdlib/` and `self_host/` get it first and this fails until the
   grammar catches up. The file count is the one README.md states, and
   `scripts/check-doc-drift.sh` recomputes it.
4. `queries/highlights.scm` is loaded against those same files. A query
   naming a node type the grammar no longer has fails at load time, so
   running it is the proof that the queries still match the node types.

**The script fails when the `tree-sitter` CLI is absent; it does not
skip.** Install it with `npm install --prefix tree-sitter-axiom
tree-sitter-cli`, or set `AXIOM_TREE_SITTER_OPTIONAL=1` to skip on
purpose. It used to exit 0 with the CLI missing — the state of any
machine that had not run that `npm install` — so on a developer machine
it reported success without checking anything, and it hid two real
breakages at once: the grammar rejected every `struct` with fields (and
so most of `self_host/`), and the highlight-query step named a file that
had been deleted.

## Design notes

**The reference is the compiler, not a description of it.** Keyword
spellings come from `self_host/lexer.ax`; declaration and expression
shapes from `self_host/parser.ax`. Where the grammar had to make a
decision, it makes the same one the compiler makes:

- **Case decides `(data Maybe (a) (Nothing) ...)`.** `(a)` and
  `(Nothing)` are both `'(' identifier ')'`. The compiler's
  `collectTyParams` takes a parenthesised group as the type-parameter
  list exactly when it is empty or its names start lowercase, so
  `type_parameters` holds only lowercase tokens and constructors only
  uppercase ones. The alternatives tree-sitter offered — a precedence or
  a declared conflict — would both have guessed at something the
  compiler decides by case.
- **There is no parenthesised-type rule**, because `parseType` has none:
  a parenthesised group in type position must be headed by `->`, `*`,
  `linear`, a comma-separated tuple, `()`, or a capitalised name. Adding
  one made the grammar ambiguous in two places and matched nothing real.
- **Arity rules are minimums, not exact counts.** `(if)` parses as an
  `if_expression` with no operands. The compiler reports `AX2001`; this
  grammar's job is to keep producing a usable tree for input that is
  nearly always mid-edit, because a grammar that fails on incomplete input
  produces an `ERROR` that swallows the rest of the file and collapses
  highlighting exactly when the author most needs it.
- **Removed constructs parse.** `union`, `region` and `foreign` are gone
  from the language but still reserved, and the compiler reports `AX2004`
  for them.
  A `removed_form` node consumes the whole dead form, so an editor gets one
  bounded region to mark as an error instead of an anonymous `ERROR` whose
  extent depends on where recovery landed — and so the trailing fields of
  an old `union` are not reinterpreted as top-level declarations.
- **Nesting block comments are an external scanner**, not a rule.
  Nesting is not expressible as a tree-sitter token, and the obvious
  chunked-regex spelling disagrees with the compiler on inputs the
  compiler has an opinion about — `#| a||# |#` closes at the `|#` inside
  `a||#` for `skipBlockComment` in `self_host/lexer.ax` and does not for
  the regex. `src/scanner.c` reproduces that function byte for byte.

**Four declared conflicts, no precedence hacks.** Each is a place where
the language itself is locally ambiguous and the ambiguity resolves a token
or two later, which is what GLR is for:

| Conflict | Ambiguity |
|---|---|
| `struct_declaration` / `struct_construction` | `(struct Point ...)` — a declaration if the body is `(field : Type)` items, a construction if it is expressions. Visible only at the `:`. |
| `type_parameters` / `application` | the same thing one level down: `()` in `(struct Point () ...)`. |
| `type_parameters` / `_expression` | and once more for `(struct P (x))`, where the group is a parameter list or a construction argument, and the two diverge at a `:` two tokens further on than the lexer can see. Spelling the parameters as `identifier` rather than a `type_variable` token is what moved that decision to the parser; before it, every `struct` with fields failed to parse. |
| `effect` / `_expression` | `(foo)` after a handle body — a one-element custom effect list, or the handler. `parseHandleExpr` resolves this greedily, reading an effect list whenever the token after the body opens a paren; rule order reproduces that. |

Notably absent: any `prec()` on a conflicting rule. A precedence there
would assert that one reading is always preferred, which is false in all
four cases.

## Known gaps

- **No `injections.scm`, `locals.scm`, or `folds.scm`.** Highlighting and
  structural selection work; scope-aware rename and code folding do not.
- **No language bindings** (`bindings/node`, `bindings/rust`). The grammar
  is verified through the CLI. Bindings are needed for the LSP to consume
  it in-process, and that is when they should be added — generated bindings
  that nothing imports are just files to keep in sync.
- **`handle` has an ambiguity inherited from the language.** The greedy
  reading is reproduced faithfully, but it is greedy in the compiler too,
  and the right fix is in the language rather than here.
