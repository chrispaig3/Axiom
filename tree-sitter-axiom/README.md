# tree-sitter-axiom

A Tree-sitter grammar for Axiom. It gives your editor syntax
highlighting, structural selection and incremental reparsing.

```text
tree-sitter-axiom/
├── grammar.js               the grammar
├── src/scanner.c            the external scanner: nesting `#| ... |#`
├── src/parser.c             generated from grammar.js, committed
├── queries/highlights.scm   highlighting captures
├── queries/rainbows.scm     bracket pairs by nesting depth (Helix `rainbow-brackets`, rainbow-delimiters.nvim)
├── test/corpus/             tree-shape tests
└── tree-sitter.json         CLI configuration
```

<a id="verifying-it"></a>
## Check the grammar

```bash
./scripts/check-tree-sitter.sh
```

The script needs the `tree-sitter` CLI, and fails if it is missing.
Install it with `npm install --prefix tree-sitter-axiom
tree-sitter-cli`, or set `AXIOM_TREE_SITTER_OPTIONAL=1` to skip the
grammar checks.

It runs these checks in order:

1. Every Axiom code block in the documents it sweeps balances its
   delimiters. This needs neither the CLI nor a compiler, so it runs
   first, on any machine.
2. `tree-sitter generate` must reproduce the committed `src/` exactly,
   so a grammar change can't land without its regenerated parser.
3. `tree-sitter test` runs the corpus in `test/corpus/`, which pins the
   tree *shape* of each construct. A change that still parses
   everything but reorganises the tree would silently break every
   query. This catches it.
4. Every `.ax` file in the repository must parse with no `ERROR` node.
   This check matters most. Whoever changes the grammar writes the
   corpus, but `stdlib/` and `self_host/` get new language forms first,
   so this fails until the grammar catches up. The file count is the
   one the [root README](../README.md) states, and
   `scripts/check-doc-drift.sh` recomputes it.
5. `queries/highlights.scm` and `queries/rainbows.scm` are loaded
   against those same files. A query that names a node type the grammar
   no longer has fails to load, so this proves the queries still match.
   The rainbow query must also capture brackets.

## Design notes

The grammar follows the compiler. Keyword spellings come from
`self_host/lexer.ax`, and declaration and expression shapes from
`self_host/parser.ax`. Where the grammar has to make a choice, it makes
the one the compiler makes.

- Case decides `(data Maybe (a) (Nothing) ...)`. `(a)` and `(Nothing)`
  are both `'(' identifier ')'`. The compiler's `collectTyParams` treats
  a parenthesised group as the type-parameter list exactly when it is
  empty or its names start lowercase. So `type_parameters` holds only
  lowercase tokens, and constructors only uppercase ones. A precedence
  or a declared conflict would have guessed at something the compiler
  decides by case.
- There is no parenthesised-type rule, because `parseType` has none. In
  type position, a parenthesised group must be headed by `->`, `*`,
  `linear`, a comma-separated tuple, `()` or a capitalised name. Adding
  such a rule made the grammar ambiguous in two places and matched
  nothing real.
- Arity rules are minimums. `(if)` parses as an `if_expression` with no
  operands, and the compiler reports `AX2001`. Code in an editor is
  nearly always mid-edit. A grammar that fails on incomplete input
  produces an `ERROR` that swallows the rest of the file and breaks
  highlighting just when you need it.
- Removed constructs still parse. `union`, `region` and `foreign` are
  gone from the language but still reserved, and the compiler reports
  `AX2004` for them. A `removed_form` node consumes the whole form, so
  your editor gets one bounded region to mark as an error. The trailing
  fields of an old `union` aren't misread as top-level declarations.
- Nesting block comments use an external scanner, `src/scanner.c`.
  Tree-sitter can't express nesting as a token, and the obvious
  chunked regex disagrees with the compiler. For example, `#| a||# |#`
  closes at the `|#` inside `a||#` for `skipBlockComment` in
  `self_host/lexer.ax`, but not for the regex. The scanner reproduces
  that function byte for byte.

### Declared conflicts

Where the language is locally ambiguous and the ambiguity resolves a
token or two later, the grammar declares a conflict and lets GLR
parsing carry both readings. These are the main ones:

| Conflict | Ambiguity |
|---|---|
| `struct_declaration` / `struct_construction` | `(struct Point ...)` is a declaration if the body is `(field : Type)` items, and a construction if it is expressions. The difference shows only at the `:`. |
| `type_parameters` / `application` | The same ambiguity one level down: `()` in `(struct Point () ...)`. |
| `type_parameters` / `_expression` | Once more for `(struct P (x))`, where the group is a parameter list or a construction argument. The two diverge at a `:` two tokens further on than the lexer can see. Spelling the parameters as `identifier`, not a `type_variable` token, moves that decision to the parser. |
| `effect` / `_expression` | `(foo)` after a handle body is a one-element custom effect list, or the handler. `parseHandleExpr` resolves this greedily: it reads an effect list whenever the token after the body opens a paren. Rule order reproduces that. |

The rest cover `(struct S (msg String))`, a field with no `:` that the
compiler refuses with `AX3056` but the grammar must still parse, and
`(data Foo (a))`, where a group of lowercase names could be type
parameters or a constructor.

No conflicting rule has a static `prec()`. That would assert that one
reading is always preferred, which is false in these cases. Where the
compiler does decide, a `prec.dynamic` on the type-parameter list of
`struct` and `data` settles the collision the same way.

## Known gaps

- No `injections.scm`, `locals.scm` or `folds.scm`. Highlighting and
  structural selection work. Scope-aware rename and code folding don't.
- No language bindings (`bindings/node`, `bindings/rust`). The grammar
  is verified through the CLI. The LSP will need bindings to use the
  grammar in-process, and that is when they should be added. Until
  something imports them, they would only be files to keep in sync.
- `handle` inherits an ambiguity from the language. The grammar
  reproduces the compiler's greedy reading, and the right fix belongs in
  the language, not here.
