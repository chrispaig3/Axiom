# tree-sitter-axiom

Tree-sitter grammar for Axiom, for editor support: syntax highlighting,
structural selection, and incremental reparsing.

```
tree-sitter-axiom/
├── grammar.js               the grammar
├── queries/highlights.scm   highlighting captures
├── test/corpus/             tree-shape tests
└── tree-sitter.json         CLI configuration
```

## Verifying it

```bash
./scripts/check-tree-sitter.sh
```

Two checks, and the second is the one that matters:

1. `tree-sitter test` runs the corpus in `test/corpus/`, pinning the tree
   *shape* per construct. A change that still parses everything but
   reorganises the tree breaks every query silently; this catches it.
2. Every `.ax` file in the repository is parsed and must produce no
   `ERROR` node. The corpus is written by whoever changed the grammar; the
   standard library and the demos are not, so this is the check that keeps
   the grammar honest. Currently 18/18 files, ~18 MB/s.

The script skips cleanly if the `tree-sitter` CLI is absent — a
contributor working on the compiler has no reason to install a JavaScript
toolchain.

## Design notes

**The reference is the compiler, not a description of it.** Keyword
spellings come from `axiom-lexer/src/lib.rs`; declaration and expression
shapes from `axiom-parser/src/lib.rs`. Where the grammar had to make a
decision, it makes the same one the compiler makes:

- **Case decides `(data Maybe (a) (Nothing) ...)`.** `(a)` and
  `(Nothing)` are both `'(' identifier ')'`. The compiler's
  `looks_like_tyvar_list` accepts a parenthesised group as a type
  parameter list exactly when every name in it starts lowercase, so
  `type_parameters` holds only lowercase tokens and constructors only
  uppercase ones. The alternatives tree-sitter offered — a precedence or a
  declared conflict — would both have guessed at something the compiler
  decides by case.
- **There is no parenthesised-type rule**, because `parse_type` has none:
  a parenthesised group in type position must be headed by `->`, `*`,
  `linear`, a comma-separated tuple, `()`, or a capitalised name. Adding
  one made the grammar ambiguous in two places and matched nothing real.
- **Arity rules are minimums, not exact counts.** `(if)` parses as an
  `if_expression` with no operands. The compiler reports `AX2001`; this
  grammar's job is to keep producing a usable tree for input that is
  nearly always mid-edit, because a grammar that fails on incomplete input
  produces an `ERROR` that swallows the rest of the file and collapses
  highlighting exactly when the author most needs it.
- **Removed constructs parse.** `union` and `region` are gone from the
  language but still reserved, and the compiler reports `AX2004` for them.
  A `removed_form` node consumes the whole dead form, so an editor gets one
  bounded region to mark as an error instead of an anonymous `ERROR` whose
  extent depends on where recovery landed — and so the trailing fields of
  an old `union` are not reinterpreted as top-level declarations.

**Three declared conflicts, no precedence hacks.** Each is a place where
the language itself is locally ambiguous and the ambiguity resolves a token
or two later, which is what GLR is for:

| Conflict | Ambiguity |
|---|---|
| `struct_declaration` / `struct_construction` | `(struct Point ...)` — a declaration if the body is `(field : Type)` items, a construction if it is expressions. Visible only at the `:`. |
| `type_parameters` / `application` | the same thing one level down: `()` in `(struct Point () ...)`. |
| `effect` / `_expression` | `(foo)` after a handle body — a one-element custom effect list, or the handler. `parse_handle` resolves this greedily; rule order reproduces that. |

Notably absent: any `prec()` on a conflicting rule. A precedence there
would assert that one reading is always preferred, which is false in all
three cases.

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
