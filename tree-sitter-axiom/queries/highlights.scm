; Syntax highlighting for Axiom.
;
; Capture names follow the tree-sitter convention set used by Neovim,
; Helix, and the tree-sitter CLI's own `highlight` command, so this file
; works in all three without a per-editor variant.
;
; Consumers disagree about which of two overlapping patterns wins:
; `tree-sitter-highlight` and most published grammars take the first, and
; recent Neovim takes the last unless an explicit priority is set. Rather
; than pick a side, this file avoids overlaps wherever the two answers
; would *differ*, by scoping each pattern to the context that determines
; the role.
;
; Concretely: there is no blanket `(constructor_identifier) @type` rule,
; because the same token is a type in `(Maybe Int)` and a data constructor
; in `(Just a)`, and a blanket rule gets one of them wrong under either
; convention. The one overlap left is the catch-all `(identifier)
; @variable` at the end of the file, where the fallback is a strictly worse
; but still correct answer.

; ---------------------------------------------------------------
; Comments and metadata
; ---------------------------------------------------------------

(comment) @comment
(block_comment) @comment

; AXTAGs are agent-authored metadata that the compiler validates, not
; free-form prose. Highlighting them apart from comments is the point:
; `;@axiom:effect(io)` is a claim the compiler will check and reject
; (`AX3010`), and it should not look like a note to a human.
(axtag) @attribute

; ---------------------------------------------------------------
; Literals
; ---------------------------------------------------------------

(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
(character_literal) @character
(string_literal) @string

; ---------------------------------------------------------------
; Types
; ---------------------------------------------------------------

(builtin_type) @type.builtin
(unit_type) @type.builtin
(type_variable) @variable.parameter

; Scoped to type position. `(type_constructor (constructor_identifier))`
; matches both spellings - the bare `Maybe` and the applied `(Maybe Int)`,
; whose head carries a `name:` field - because they are the same node.
(type_constructor (constructor_identifier) @type)

(builtin_effect) @keyword.modifier
(effect (identifier) @keyword.modifier)

; ---------------------------------------------------------------
; Declarations
;
; A declaration's name is highlighted by role rather than by shape, which
; is the whole reason for the `field(...)` labels in the grammar: `Point`
; in `(struct Point ...)` is a type, and `add` in `(fn (add x y) ...)` is
; a function, and neither is inferable from the token alone.
; ---------------------------------------------------------------

(function_definition name: (identifier) @function)
(function_definition parameter: (identifier) @variable.parameter)

(data_declaration name: (identifier) @type)
(data_constructor name: (constructor_identifier) @constructor)

(struct_declaration name: (identifier) @type)
(field_declaration name: (identifier) @variable.member)

(type_alias name: (identifier) @type.definition)

(trait_declaration name: (identifier) @type)
(trait_method name: (identifier) @function.method)
(impl_declaration trait: (identifier) @type)
(impl_method name: (identifier) @function.method)

(effect_declaration name: (identifier) @keyword.modifier)
(effect_operation name: (identifier) @function.method)

(import module: (module_path) @module)
(import name: (identifier) @variable)

; A top-level signature's subject is a bare identifier naming the
; function it describes. An inline ascription's subject is an arbitrary
; expression, and this pattern correctly does not match it.
(type_signature subject: (identifier) @function)

; ---------------------------------------------------------------
; Patterns
; ---------------------------------------------------------------

(wildcard_pattern) @character.special
(constructor_pattern constructor: (constructor_identifier) @constructor)
(let_binding pattern: (identifier) @variable)

; ---------------------------------------------------------------
; Expressions
; ---------------------------------------------------------------

; The head of an application is the thing being called. Axiom has no
; operator syntax - `+` is an ordinary identifier in head position - so
; this single rule is what makes both `(f x)` and `(+ 1 2)` highlight
; sensibly, and it is why there is no operator pattern below.
(application
  .
  (identifier) @function.call)

(struct_construction name: (identifier) @constructor)

; ---------------------------------------------------------------
; Keywords
; ---------------------------------------------------------------

[
  "fn"
  "define"
  "lambda"
] @keyword.function

[
  "data"
  "struct"
  "type"
  "trait"
  "impl"
  "effect"
] @keyword.type

[
  "if"
  "cond"
  "match"
  "else"
] @keyword.conditional

; The two loop heads. `while` was missing from this file before `for`
; existed, so this group is both of them rather than the new one alone.
[
  "while"
  "for"
] @keyword.repeat

[
  "let"
  "handle"
  "where"
  "pub"
  "import"
] @keyword

[
  "alloc"
  "sizeof"
  "alignof"
  "cast"
  "mut"
] @keyword.modifier

; ---------------------------------------------------------------
; Removed constructs
;
; `union`, `region` and `foreign` parse, so that an editor can mark the
; dead form as one bounded region instead of showing an anonymous ERROR
; whose extent depends on where recovery landed. They are highlighted as
; errors because that is what the compiler reports (`AX2004`).
; ---------------------------------------------------------------

(removed_keyword) @error
(removed_form) @error

; ---------------------------------------------------------------
; Punctuation
; ---------------------------------------------------------------

[
  "::"
  "->"
  ":"
  "="
  "!"
  "*"
  ","
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Everything not captured above is a plain variable reference. Last, so
; that every rule above wins over it.
(identifier) @variable
