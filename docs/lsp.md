# The Axiom language server

`axiom lsp` is the language server. It is `self_host/lsp.ax`, one
module of the self-hosted compiler, and it owns the protocol and
nothing else: every diagnostic it publishes comes from the same
`parseModuleWith`/`checkModule` pair that `axiom check` runs, and every
answer below is read off the compiler's own parse tree. This document
says how to run it, how to point four editors at it, what each request
answers and what it deliberately refuses, the legend its highlighting
uses, and the one cost rule the whole design follows.

Every claim here is held by `scripts/check-lsp-selfhost.sh`, which
builds a server from `self_host/` and drives it with
`tests/lsp/drive.py`; each section names the part of that gate that
holds it. Counts are kept out of the prose on purpose —
`scripts/check-doc-drift.sh` recomputes every number a document
states, and the gate's own output prints the current ones — and the
one release that grew the server from four questions to the set below
is [CHANGELOG.md](../CHANGELOG.md) `## 0.3.5`, which records what was
measured when each request landed.

## Running it

```bash
axiom lsp
```

That is the whole command line, and `axiom help lsp` says so: the
server speaks JSON-RPC 2.0 over stdin and stdout with the base
protocol's `Content-Length` framing, takes no operand, accepts no flag
of its own, and writes nothing else to stdout. It writes nothing to
stderr either — a session of `initialize`, `shutdown`, `exit` leaves
stderr empty. `scripts/check-driver.sh` holds `--help` to the
driver's accept-chain, so a flag the subcommand grew would have to
appear there.

A session from a shell, for when an editor's log is not enough:

```bash
python3 - <<'PY'
import json, subprocess
def frame(m):
    b = json.dumps(m).encode()
    return b"Content-Length: %d\r\n\r\n" % len(b) + b
msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"processId": None, "rootUri": None, "capabilities": {}}},
        {"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None},
        {"jsonrpc": "2.0", "method": "exit", "params": None}]
p = subprocess.run(["axiom", "lsp"], input=b"".join(map(frame, msgs)),
                   capture_output=True)
print(p.stdout.decode())
print("exit", p.returncode)
PY
```

The first reply is the `initialize` result: the capabilities object
the rest of this document walks through, and `serverInfo` naming
`axiom` and the compiler's version. The exit status is `0` after a
`shutdown`, and `1` when the client sent `exit` without one or closed
the pipe — measured on all three endings against the release binary.
The framed byte stream of a fixed session, capabilities included, is
pinned by the goldens under `tests/lsp/`.

What the lifecycle does, and what it does not:

- **Sync is full-text**, `textDocumentSync: 1`. Every `didChange`
  carries the whole document — the server reads the LAST content
  change of the notification — because the checker takes a whole
  source string anyway, and an incremental store would exist only to
  be re-flattened before every check. `didOpen`, `didChange` and
  `didClose` are the three notifications it reads; a `didSave` is
  dropped, as any notification it does not know is.
- **Diagnostics are published on every `didOpen` and `didChange`**,
  under the document's own URI, and they are `axiom check`'s: a
  lexical error first, then a parse error with a span on the token
  that failed, then `AX5001` for an import that does not resolve, then
  the expander's refusals alone when it refused, else the expander's
  and the checker's diagnostics merged in the compiler's order. Each
  carries the `AX` code as `code`, `axiom` as `source`, and the
  message's first line followed by its `help:` paragraph. Only THIS
  document's diagnostics are published: a diagnostic the checker
  raised inside an imported module is not attributed to the file that
  imports it — open that module and it is published there. `didClose`
  publishes an empty list, which is how a server retracts squiggles.
  `tests/lsp/expected-diagnostics.txt` is the manifest every fixture's
  diagnostics are held to, by severity, code, an anchor string and the
  message line, with positions recomputed in Python from the bytes.
- **Imports resolve as `axiom check` resolves them** from the file the
  URI names: the entry file's directory, an `axiom.pkg`'s `depend`
  directories, then `$AXIOM_PATH`. If `axiom check f.ax` finds the
  standard library from the shell your editor launches, the server
  finds it too; a half-typed `(import Fo` is answered as "this
  document alone", never as an error and never by a dead server
  (`lspPreflight` in `self_host/lsp.ax` walks the imports non-fatally
  before anything resolves).
- **Positions are UTF-16 code units**, the protocol's default.
  `tests/lsp/030-utf16-columns.ax` is the fixture that pins it.
- **A request the server does not know is answered with `-32601`**
  (`method not found: <name>`), a notification it does not know is
  dropped, and a message that is not JSON is dropped; `shutdown` is
  answered `null`. One `initialize` per process: there is no
  workspace-folder state to update.
- **Memory is flat across a session.** The arena is reset after every
  message, keeping the document store and the reader's unconsumed
  bytes; `drive.py`'s editing session, which edits one document many
  times and requires the process not to grow, is the check.

## Editor setup

The server is found through the editor's `PATH`, so `axiom` must be on
it — or write the absolute path where the configurations below say
`"axiom"`. Source files end in `.ax`; the server does not read the
`languageId` a client sends, so name the filetype whatever your editor
wants, and the configurations below call it `axiom`. The two code-lens
commands `axiom.run` and `axiom.expandMacro` are the client's to
define (see [Changing and running](#changing-and-running)); each
configuration below defines them where the editor can.

### Neovim

Neovim's built-in client. Semantic tokens are requested automatically
in 0.9 and later whenever a server advertises
`semanticTokensProvider`; put the cursor on an identifier and run
`:Inspect` — the *Semantic Tokens* section lists groups such as
`@lsp.type.function.axiom` and `@lsp.mod.declaration.axiom`. Nothing
below turns them on, because nothing has to.

```lua
-- init.lua
vim.filetype.add({ extension = { ax = "axiom" } })

-- Neovim 0.11+: a named client configuration, enabled for the filetype.
vim.lsp.config("axiom", {
  cmd = { "axiom", "lsp" },
  filetypes = { "axiom" },
  root_markers = { "axiom.pkg", ".git" },
})
vim.lsp.enable("axiom")

-- Neovim 0.10: start the client by hand instead of the two calls above.
-- vim.api.nvim_create_autocmd("FileType", {
--   pattern = "axiom",
--   callback = function(ev)
--     vim.lsp.start({
--       name = "axiom",
--       cmd = { "axiom", "lsp" },
--       root_dir = vim.fs.root(ev.buf, { "axiom.pkg", ".git" }),
--     })
--   end,
-- })

-- The two commands the code lenses name. The server never runs them.
vim.lsp.commands["axiom.run"] = function(command)
  vim.cmd.split()
  vim.cmd.terminal("axiom run " .. vim.fn.shellescape(command.arguments[1]))
end
vim.lsp.commands["axiom.expandMacro"] = function(command)
  local uri, position = command.arguments[1], command.arguments[2]
  vim.lsp.buf_request(0, "axiom/expandMacro",
    { textDocument = { uri = uri }, position = position },
    function(err, result)
      if err or not result then
        vim.notify("nothing to expand here")
        return
      end
      vim.cmd.new()
      vim.bo.filetype, vim.bo.buftype = "axiom", "nofile"
      vim.api.nvim_buf_set_lines(0, 0, -1, false,
        vim.split("; " .. result.name .. "\n" .. result.expansion, "\n"))
    end)
end

-- Hints and lenses are off until asked for.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= "axiom" then return end
    vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
    vim.lsp.codelens.refresh({ bufnr = ev.buf })
    vim.keymap.set("n", "<leader>l", vim.lsp.codelens.run, { buffer = ev.buf })
  end,
})
```

`:checkhealth vim.lsp` shows the client attached and the capabilities
it received. Highlighting from the tree-sitter grammar is separate and
optional — the semantic tokens colour a buffer with no grammar
installed — and registering it is nvim-treesitter's business, pointed
at [`tree-sitter-axiom/`](../tree-sitter-axiom/README.md) in a
checkout:

```lua
require("nvim-treesitter.parsers").get_parser_configs().axiom = {
  install_info = {
    url = "/path/to/axiom/tree-sitter-axiom",
    files = { "src/parser.c", "src/scanner.c" },
  },
  filetype = "axiom",
}
-- then :TSInstall axiom, and copy tree-sitter-axiom/queries/highlights.scm
-- to a queries/axiom/highlights.scm directory on the runtimepath.
```

### Helix

Helix highlights with tree-sitter alone and does not consume semantic
tokens or code lenses, so the grammar matters here and the two
lens commands are out of reach. Everything else — definition,
references, rename, hover, completion, signature help, inlay hints,
document and workspace symbols, formatting, code actions — is the
built-in client's.

```toml
# ~/.config/helix/languages.toml
[language-server.axiom]
command = "axiom"
args = ["lsp"]

[[language]]
name = "axiom"
scope = "source.axiom"
file-types = ["ax"]
roots = ["axiom.pkg", ".git"]
comment-token = ";"
block-comment-tokens = { start = "#|", end = "|#" }
indent = { tab-width = 2, unit = "  " }
language-servers = ["axiom"]

[[grammar]]
name = "axiom"
source = { path = "/path/to/axiom/tree-sitter-axiom" }
```

Then `hx --grammar build`, and copy
`tree-sitter-axiom/queries/highlights.scm` to
`~/.config/helix/runtime/queries/axiom/highlights.scm`. The query file
is written in nvim-treesitter's capture names, and a capture Helix's
themes do not spell (`@module`, `@keyword.modifier`, `@number.float`)
is left uncoloured rather than wrong. `hx --health axiom` reports
whether the grammar and the server were both found. Inlay hints are
off in Helix until `config.toml` says `[editor.lsp]
display-inlay-hints = true`.

### Emacs (eglot)

Eglot is in Emacs 29 and later. It consumes neither semantic tokens
nor code lenses, so highlighting is whatever the major mode does and
the `Run` lens is not reachable; `lsp-mode` does both, with
`lsp-semantic-tokens-enable` and `lsp-lens-mode`, and is configured
the same way with `lsp-register-client`. Definition is `M-.`,
references `M-?`, hover and signature help are `eldoc`, the outline is
`imenu`, and `eglot-rename`, `eglot-code-actions` and
`eglot-format-buffer` are the rest.

```elisp
;; init.el
(define-derived-mode axiom-mode lisp-data-mode "Axiom"
  "Axiom source: s-expressions, `;' line comments.")
(add-to-list 'auto-mode-alist '("\\.ax\\'" . axiom-mode))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '(axiom-mode . ("axiom" "lsp"))))
(add-hook 'axiom-mode-hook #'eglot-ensure)

;; The custom request, as a command: the expansion in a new buffer.
;; `eglot--' helpers are Eglot's internals and may move between releases.
(defun axiom-expand-macro ()
  "Show what the macro at point generated."
  (interactive)
  (let ((res (jsonrpc-request (eglot--current-server-or-lose) :axiom/expandMacro
                              (list :textDocument (eglot--TextDocumentIdentifier)
                                    :position (eglot--pos-to-lsp-position)))))
    (if (null res)
        (message "Nothing to expand here")
      (with-current-buffer
          (get-buffer-create (format "*axiom expand %s*" (plist-get res :name)))
        (erase-buffer)
        (insert (plist-get res :expansion) "\n")
        (axiom-mode)
        (pop-to-buffer (current-buffer))))))
```

### VS Code

There is no published Axiom extension. What follows is a snippet to
build one from: two files in a directory, `npm install`, then open the
directory in VS Code and press F5 for an Extension Development Host
with the extension loaded. `vscode-languageclient` asks the server for
semantic tokens, inlay hints, code lenses and everything else it
advertises without being told to; the two commands are the only code
that is not boilerplate.

```json
{
  "name": "axiom-editor",
  "displayName": "Axiom",
  "version": "0.0.1",
  "publisher": "local",
  "engines": { "vscode": "^1.85.0" },
  "main": "./extension.js",
  "activationEvents": ["onLanguage:axiom"],
  "contributes": {
    "languages": [{ "id": "axiom", "aliases": ["Axiom"], "extensions": [".ax"] }],
    "commands": [
      { "command": "axiom.run", "title": "Axiom: Run" },
      { "command": "axiom.expandMacro", "title": "Axiom: Expand Macro" }
    ]
  },
  "dependencies": { "vscode-languageclient": "^9.0.1" }
}
```

```js
// extension.js
const vscode = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");
let client;
function activate(context) {
  client = new LanguageClient("axiom", "Axiom",
    { command: "axiom", args: ["lsp"] },
    { documentSelector: [{ scheme: "file", language: "axiom" }] });
  context.subscriptions.push(
    vscode.commands.registerCommand("axiom.run", (path) => {
      const t = vscode.window.createTerminal("axiom run");
      t.show();
      t.sendText("axiom run " + JSON.stringify(path));
    }),
    vscode.commands.registerCommand("axiom.expandMacro", async (uri, position) => {
      const r = await client.sendRequest("axiom/expandMacro", { textDocument: { uri }, position });
      if (!r) { vscode.window.showInformationMessage("Nothing to expand here"); return; }
      const doc = await vscode.workspace.openTextDocument(
        { language: "axiom", content: "; " + r.name + "\n" + r.expansion + "\n" });
      await vscode.window.showTextDocument(doc, { preview: true });
    }));
  client.start();
}
function deactivate() { return client && client.stop(); }
module.exports = { activate, deactivate };
```

Two things a builder adds next: a TextMate grammar under
`contributes.grammars`, without which the semantic tokens are the
whole of the highlighting — and `"editor.semanticHighlighting.enabled":
true` in settings, since some themes leave it to the theme — and a
`language-configuration.json` naming `;` as the line comment and the
bracket pairs. *Developer: Inspect Editor Tokens and Scopes* shows,
for the token under the cursor, the semantic token type and the
TextMate scope it was mapped to.

## What each request answers

The requests are grouped as README.md's *Editor support* row groups
them. Each paragraph says what the request answers, what it
deliberately does not, and where in `tests/lsp/drive.py` the derived
check lives — a check whose expected answer is computed from a
document the driver writes itself, so that re-blessing a golden cannot
satisfy it. `SECTION NAV TESTS`, `SECTION VIEW TESTS` and
`SECTION FIX TESTS` are the marker comments to search for.

Two facts hold for every request that takes a position. The word
under the cursor is found by the same string-and-comment-aware
scanner (`lspWordSpan`, `lspFormEnd`), so no two requests disagree
about where a form ends; and a document that does not parse answers
`null` or `[]` — except for the requests that work from the bytes,
which are named below. The sweep at the end of
`scripts/check-lsp-selfhost.sh` fires every advertised request at
every 97th byte of a real standard-library module, at the positions
that break scanners (offset 0, EOF, one past EOF, a line past the end,
inside a string, inside a comment, on `(`, on `)`), at the same module
cut off mid-form, and at an empty document, and requires an answer to
every id, no error, and a server still alive to say `shutdown`. Its
method table is DERIVED from the capabilities the server advertises,
so a key it cannot build a request for fails the gate.

This document is used for the examples below; it checks clean, and
the answers quoted are the release binary's.

```axiom
(import IO)

; A tag function for the data it is given.
(pub macro deriveTag
  ((deriveTag T)
   (pub :: (syntax/join tag T) Int)
   (pub fn ((syntax/join tag T)) 7)))

(data Colour
  (Red)
  (Green))

(deriveTag Colour)

; Add one.
(:: bump (-> Int Int))
(fn (bump x) (+ x 1))

;@axiom:effect(io)
(fn (main)
  {
    (println "hi")
    (bump 4)
  })
```

### Navigation

**`textDocument/definition`.** Where the name under the cursor is
bound, asked in the language's own order: the innermost local binding
first — a `let` name, a `fn` or `lambda` parameter, a pattern
variable, landing on the binder — then this document's declarations,
then the merged declarations of every module this document imports,
answering a `Location` in that module's own file. A macro invocation
is a reference to its `macro` declaration (`MAC-TOOL-2` in
[macro-system.md](macro-system.md)). What it does not do: a builtin
(`Int`, `+`), a keyword and a name nothing declares answer `null`; a
name a macro would generate has no definition, because nothing has
expanded it; and an import that does not resolve narrows the search
to this document rather than failing it.

**`textDocument/references` and `textDocument/documentHighlight`.**
Every occurrence of the same BINDING, not the same spelling: the
walk records each occurrence with the key of what it resolves to, so
the `i` of one function is not the `i` of another, and a `let` that
shadows a parameter is a different name from it. Type positions —
the names inside every `::`, `data`, `struct`, `type`, `impl` and
`trait` form — are read from the bytes, since type nodes carry no
span, and resolved against the type table alone, so a `fn` spelled
like a `data` is not the same name. `references` reaches every OTHER
open document whose imports resolve to this file, each under its own
URI, and honours `includeDeclaration`; it does not open files the
editor has not, so a reference in a closed module is not listed.
`documentHighlight` is the same set within one document, with the
binder as the `Write` kind and reads as `Read`. The gate derives every
expected `Location` from documents the driver writes — a parameter
with and without its declaration, a `let` from its read, a type in a
signature, a struct field and an alias — and the changelog's review
section records the measurement beyond it: on four real files,
`references` on twenty top-level names equals a whole-identifier grep
of the code.

**`textDocument/prepareRename` and `textDocument/rename`.**
`prepareRename` answers the word's range for a name this server will
rename, and `null` for one it will not: a name declared in another
module, even an open one — renaming across files the server did not
open would leave a broken workspace, and a standard-library name must
never be renamed from a client — a builtin, an effect, a keyword,
`_`, and a parameter whose position could not be recovered from the
header's bytes. `rename` refuses, with `null`, a new name the lexer
would not read as one identifier, a keyword, the old name itself, and
a collision: for a local, a name already bound in an enclosing or the
same scope or one the renamed binding would capture (a second walk
with a probe decides this, inside the scope stack); for a declaration,
a name this document or any importing document already spells
anywhere, because a rename that makes a call resolve somewhere else
is a change of meaning disguised as a change of spelling. The edit
covers every open importing document. The gate APPLIES a cross-file
rename in Python, writes both files, reopens them and requires the
checker to publish nothing for the pair.

**`textDocument/typeDefinition`.** From a signed function's result,
a header parameter or a constructor to the `data`, `struct` or `type`
that declares its type, in this document or an imported one. `null`
for a builtin type, for a `fn` with no `::`, and for a position that
is none of those three.

### Reading

**`textDocument/hover`.** Markdown with an `axiom` fence quoting the
declaration, the module below it when the name was imported, and the
comment paragraph written above the declaration. A `fn` is quoted as
its `(:: f T)` signature rather than its body, and its paragraph is
read from above the signature, because that is where this language
puts it; a `fn` with no signature is quoted as its first line. A
`data`, `struct` or `macro` is quoted whole, cut to a tooltip's
height by `lspClampLines`. A local answers from the walk: a parameter
of `bump` answers

```text
x : Int

parameter of `bump`
```

with the type cut from the signature's arrow. The `range` is the word
under the cursor, not the declaration, which for an imported name is
in a different file. `null` for a builtin, a keyword or a name nothing
declares. The gate cuts every quoted form and every paragraph out of
the document itself — a second implementation, in Python, of
`lspFormText` and `lspDocComment` — and compares.

**`textDocument/completion`.** In this order: the head keywords the
parser dispatches on (extracted from the `kwEq` call sites of
`self_host/parser.ax` by the gate, so the copy in `lsp.ax` is a
checked claim), this document's declarations and the constructors its
`data` forms name, and every imported module's declarations under
their bare names — a local name shadowing an imported one and both
shadowing a keyword. The list is filtered on the prefix under the
cursor, capped at `LSP_COMPL_MAX`, and sent `isIncomplete: true`,
which tells the client to ask again on the next keystroke; `(` is the
trigger character. A document that does not parse still completes
keywords — the normal case, since a file is unparseable exactly while
a form is half written. It does not offer a name a macro would
generate: `(deriveTag Colour)` does not put `tagColour` in the menu,
and the gate asserts that absence.

**`textDocument/signatureHelp`.** The call the cursor is inside — a
`fn` of this document, one of its constructors, or an imported `fn`
with its module named — as `(bump x) : (-> Int Int)`, the type cut
from the `::` beside the `fn`, each parameter as the UTF-16 offset
pair that slices the label to its name, the paragraph above the
declaration as `documentation`, and `activeParameter` counted from
the bytes. `(` and space trigger it, space retriggers. A local
shadowing a top-level `fn` of the same name is asked first, so
`(fn (t7 f) (f 1 2))` beside a top-level `f` answers nothing for
`f`; a `fn` header does not answer its own signature; outside any
call it is `null`.

**`textDocument/inlayHint`.** Three hints the source does not spell:
`x:` before each argument of a call to a declared or imported `fn`
(kind `Parameter`, never before a variable spelled like the
parameter), `: Int` after each parameter in a `fn` header and
` -> Int` after the header (kind `Type`), the last two from the
signature's arrow — so a `fn` with no `::` gets no type hints. The
callee lookup is indexed per request; the measured cost of not doing
so is in the changelog.

**`textDocument/foldingRange`.** Every form and brace block whose
opener and closer sit on different lines, a run of `;` comment lines
as kind `comment`, a run of imports as kind `imports` — from a bracket
scan of the bytes, so a half-typed file still folds.

**`textDocument/selectionRange`.** Word, then the enclosing form,
then each form around it, then the document, for each position sent.

**`textDocument/documentLink`.** One link per `(import M)` whose
module the resolver's own search finds, over the dotted name as
written, targeting that file. An import that does not resolve is no
link, not an error; `resolveProvider` is false.

**`textDocument/documentSymbol`.** The outline: every `fn` and
`macro` as `Function`, every `data` as `Enum`, every `struct` as
`Struct`, each at its NAME's span, straight off the parse tree with no
checker running — a file with a type error still has an outline, and
a file that does not parse has an empty one. A `::` signature is not
listed beside its `fn`; a `trait` and a `type` alias are not listed.
`tests/lsp/expected-outline.txt` is total: a fixture publishes exactly
those rows, in that order, and `tests/lsp/060-outline.ax` is one.

**`workspace/symbol`.** Every declaration the OPEN documents can see
— their own and every module each imports — whose bare name holds the
query, case-folded, with constructors as `EnumMember` and the module
as `containerName` for an imported one; a declaration reached twice
through two open documents is listed once. The workspace this server
knows is the document store: it does not walk a directory, so a module
nothing open imports is not searched. The list stops at
`LSP_COMPL_MAX`.

### Changing and running

**`textDocument/formatting`.** One `TextEdit` over the whole document
holding the output of the same `fmtFormat` that `axiom fmt` runs;
`[]` for a document already in the formatter's normal form; `null`
for one that does not parse. The gate holds the edit's text equal,
byte for byte, to what `axiom fmt` wrote to a copy.
`textDocument/rangeFormatting` is deliberately not offered: the
formatter proves its output a fixed point of the whole file, and a
range cut out of that would be a different formatter with a weaker
proof.

**`textDocument/codeAction`.** Two kinds, both advertised in
`codeActionKinds`. `quickfix`: every machine-applicable fix the
compiler attaches to a diagnostic in the range — a help carrying a
fix span, exactly what AXDL prints after `~>` — as a preferred action,
so a code that gains a fix in `typecheck.ax` gains a quickfix without
a line changing in `lsp.ax`. `refactor.rewrite`: *Add type signature
for `f`* on a `fn` with no `::`, written from the type the checker
inferred in the parser's own spelling `(-> Int Int)`, with an
unresolved type variable lettered in order of appearance. This request
runs the pipeline (see [The cost rule](#the-cost-rule)); `[]` on a
document that does not parse. The gate applies AX3012's `mut x` at the
BINDER, AX3001's respelling at the call, and the assist, in Python,
reopens the result and requires no diagnostics at all.

**`textDocument/codeLens`.** A `▶ Run` lens over `(fn (main) ...)`
when `main` takes no parameters — that is what `axiom run` runs — and
an `Expand macro` lens over every `pub macro`. A lens carries a command
NAME and its arguments, and the server runs nothing: `axiom.run`
carries the document's filesystem path, `axiom.expandMacro` the
document's URI and the macro declaration's position, and the editor
does the rest, as rust-analyzer's `Run` lens works. On the document
above:

```json
{"range": {"start": {"line": 3, "character": 11}, "end": {"line": 3, "character": 20}},
 "command": {"title": "Expand macro", "command": "axiom.expandMacro",
             "arguments": ["file:///path/to/doc.ax", {"line": 3, "character": 11}]}}
{"range": {"start": {"line": 19, "character": 5}, "end": {"line": 19, "character": 9}},
 "command": {"title": "▶ Run", "command": "axiom.run",
             "arguments": ["/path/to/doc.ax"]}}
```

`resolveProvider` is false; `[]` on a document that does not parse.

**`axiom/expandMacro`.** The analogue of `rust-analyzer/expandMacro`,
advertised as `experimental.expandMacro: true`. Params are a text
document and a position:

```json
{"textDocument": {"uri": "file:///path/to/doc.ax"},
 "position": {"line": 12, "character": 0}}
```

and the result is the macro's name and what it generated, as Axiom
source, or `null`:

```json
{"name": "deriveTag",
 "expansion": "(pub :: tagColour Int)\n\n(pub fn (tagColour)\n  7)"}
```

On a top-level invocation — by its head or anywhere inside its bytes
— it answers that invocation's own products; on a macro declaration,
by its name or its form, everything the macro generated in this
document. The rendering is the compiler's first `ASTNode`-to-source
printer, whose promise is that the output parses and means what the
tree meant: the gate reopens the expansion as a document and requires
a clean parse with an outline of exactly the generated name, and a
differential over every top-level invocation under `tests/` and
`docs/` splices each expansion into a copy in place of the invocation
and holds `check`'s codes and `symbols`' names equal. What it does not
answer: an invocation in expression position inside a body (phase E
rewrites it in place and records nothing to attribute), an expansion
the expander refused (the refusal is already on screen as a
diagnostic), a position on anything else, and a document that does not
parse — all `null`. Three things the printer says out loud: a hygiene
binder `x.3` is written `x_3`, a `syntax/binders` variable `x#0` is
written with `_` for every byte the lexer refuses, and `Mod$name` is
written `Mod::name`. A macro whose template queries declarations
another invocation would have generated is shown without them, since
each invocation is expanded with every other removed. And a generated
`struct`'s fields print as `(name)` with no type, which is an expander
defect recorded beside `MAC-TOOL-3` in
[macro-system.md](macro-system.md), not a printer choice.

## Semantic tokens

`textDocument/semanticTokens/full` and `/range` are the highlighting
channel: every identifier coloured by WHAT IT RESOLVES TO — a
parameter, a local, a function, a type, a constructor, a macro, an
imported name — plus keywords, strings, numbers, comments, AXTAG
decorators and operators from the bytes, so a document that does not
parse is still highlighted. The capability is
`semanticTokensProvider: {legend, range: true, full: true}`; there is
no delta request. The check is the `SECTION HL TESTS` block of
`tests/lsp/drive.py`, which decodes the delta array with a second
implementation in Python, asserts the (type, modifiers) of anchors
derived from a document holding every class, holds the invariants
below over every token, and requires `range` over two lines to equal
the tokens of `full` that start on them. A server built before that
section answers the request with `-32601`, and an editor then falls
back to its grammar.

The legend, in the order the server advertises it:

| Index | Type | When it is used |
|---|---|---|
| 0 | `namespace` | the module in `(import M)` and the `Mod` of `Mod::name`; an effect named by `handle` |
| 1 | `type` | a `data`, `struct` or `type` name, at its declaration and in every type position; an uppercase-initial name outside head or pattern position that this document does not declare, or that nothing resolves |
| 2 | `enumMember` | a constructor, at its declaration and in head or pattern position; an uppercase-initial head that this document does not declare |
| 3 | `function` | a `fn` of this document; a head that resolves to an imported `fn`; in a document that does not parse, any head that is not a keyword or operator, and the name after `fn` or `::` |
| 4 | `macro` | a `macro` name, at its declaration and its invocations |
| 5 | `parameter` | a `fn` or `lambda` parameter, at its binder and every use |
| 6 | `variable` | a `let` name or pattern variable and its uses; a lowercase name this document does not declare, outside head position; any identifier the rules above do not classify |
| 7 | `keyword` | a head spelled in the parser's keyword list, `pub`, `mut`, `else`; `true` and `false` |
| 8 | `string` | a string literal, one token per line, and a char literal |
| 9 | `number` | an integer or float literal, a `-` immediately followed by a digit included |
| 10 | `comment` | a `;` line comment and each line of a `#\| \|#` block |
| 11 | `operator` | a head spelled entirely of operator bytes: `+`, `==`, `>=`, `&&`, `->` |
| 12 | `property` | a field name followed by a single `:` inside a `struct` or constructor field list |
| 13 | `decorator` | a `;@axiom:` line |

The modifiers, as bits of the fifth integer of each token:

| Bit | Modifier | When it is set |
|---|---|---|
| 1 | `declaration` | a binder; the name in a `fn`, `::`, `data`, `struct`, `type` or `macro` head; a constructor at its declaration |
| 2 | `readonly` | a `let` binder that is not `mut` |
| 4 | `modification` | the target of a `set` |
| 8 | `defaultLibrary` | every name this document does not declare — imported or builtin |

Rules a client can rely on: tokens are sorted by position and never
overlap; lengths and columns are UTF-16 code units; a token never
spans a line break, so a block comment or a multi-line string is one
token per line; brackets, braces and `_` emit nothing; `Mod::name` is
two tokens; an empty document answers `{data: []}`, never `null`; and
`range` answers only the tokens that START inside the requested range,
delta-encoded from the document's origin like `full`. In a document
that does not parse the resolving rules give way to the lexical ones:
a parameter is `variable`, a name followed by `:` is `property`, an
uppercase-initial name is `type`, and the keyword tokens are
unchanged. The cost is one parse, one line index, one occurrence walk,
one byte scan and one bucket index over the occurrences; a client
asks for `full` once on open and for ranges while scrolling.

Where the types land in an editor's theme:

| Type | Neovim group (default link) | VS Code TextMate scope (default map) |
|---|---|---|
| `namespace` | `@lsp.type.namespace` → `@module` | `entity.name.namespace` |
| `type` | `@lsp.type.type` → `@type` | `entity.name.type`; with `defaultLibrary`, `support.type` |
| `enumMember` | `@lsp.type.enumMember` → `@constant` | `variable.other.enummember` |
| `function` | `@lsp.type.function` → `@function` | `entity.name.function`; with `defaultLibrary`, `support.function` |
| `macro` | `@lsp.type.macro` → `@function.macro` | `entity.name.function.preprocessor` |
| `parameter` | `@lsp.type.parameter` → `@variable.parameter` | `variable.parameter` |
| `variable` | `@lsp.type.variable` → `@variable` | `variable.other.readwrite`; with `readonly`, `variable.other.constant` |
| `keyword` | `@lsp.type.keyword` → `@keyword` | `keyword.control` |
| `string` | `@lsp.type.string` → `@string` | `string` |
| `number` | `@lsp.type.number` → `@number` | `constant.numeric` |
| `comment` | `@lsp.type.comment` → `@comment` | `comment` |
| `operator` | `@lsp.type.operator` → `@operator` | `keyword.operator` |
| `property` | `@lsp.type.property` → `@property` | `variable.other.property` |
| `decorator` | `@lsp.type.decorator` → `@attribute` | `entity.name.decorator` |

Neovim also defines `@lsp.type.<type>.axiom`, `@lsp.mod.<modifier>.axiom`
and `@lsp.typemod.<type>.<modifier>.axiom`, most specific first, and
the modifier groups carry no colour until a colourscheme links them —
`:hi link @lsp.mod.readonly.axiom Constant` is the whole of enabling
one. VS Code exposes the modifiers to a theme's `semanticTokenColors`
as rules such as `"*.declaration"` and `"variable.modification"`; only
`readonly` and `defaultLibrary` map to a TextMate scope by default.
Helix and Eglot do not consume this channel at all.

## The cost rule

Every request that is asked per keystroke or per cursor move reads
the RAW parse tree and the document's bytes and expands no macro.
That is `MAC-TOOL-3` in [macro-system.md](macro-system.md), and the
reason is measured there: expansion is bounded but not free, and an
editor cannot wait. Each such request costs one parse, one line index
and one walk — the walk that `references` and its siblings share, the
bracket scan that folding and selection share, the bucket index that
parameter hints and signature help share — and its answer is derived
from what the file SAYS, which is why a name a macro would generate is
absent from completion, from the outline and from navigation.

Three things run the pipeline, each because the pipeline's output is
the answer: `didOpen` and `didChange`, which publish diagnostics,
because a diagnostic about generated code is exactly what expansion
is for; `codeAction`, because a quickfix is a checker diagnostic's own
fix and the assist writes what the checker inferred; and
`axiom/expandMacro`, because rendering what a macro generated is the
question being asked. None of the three is sent per keystroke — a
client asks for code actions when the cursor rests and for an
expansion on demand — and each costs about one `didOpen` of the same
document, which the editor paid on the last keystroke anyway.

The gate that holds it is `scripts/check-lsp-selfhost.sh`, and it
holds a RATIO rather than a stopwatch, so a slow runner cannot fail it
and a fast one cannot hide a regression: on a generated document with
at least `sym_floor` declarations it times `didOpen` — the whole
parse-and-check — and then `documentSymbol` and `completion` at an
empty and a filtered prefix, and fails any of them over a ceiling of
2.00x. A server that answers nothing is fast, so each measurement
carries a floor on the answer's size — the outline must carry
`sym_floor` symbols, the empty-prefix menu `item_floor` items — below
which the gate fails rather than measures. The same document and the
same `didOpen`-ratio method were used to measure every request that
landed in 0.3.5, and the numbers are in [CHANGELOG.md](../CHANGELOG.md)
`## 0.3.5` beside the change each one forced: the per-request
declaration index that replaced a first-byte bucket, and the
is-there-a-signature question the whole-document code action asks
before it walks. Run the gate and read its `ratio` lines for today's.
