; Rainbow brackets for Axiom.
;
; Helix colours a bracket pair by the nesting depth of the innermost
; `@rainbow.scope` node that contains it, so every rule that opens a
; bracket is a scope: each declaration form, each type form, each
; pattern form and each expression form - including `block`, whose
; braces are the sequencing form, and `list_literal`, whose brackets
; are a list. The token list at the end is what actually gets painted;
; a bracket that belongs to no listed scope takes the depth of the
; nearest enclosing one, which is what `source_file` is for.
;
; Consumers: Helix reads this file as `rainbows.scm` from its runtime
; queries directory (`editor.rainbow-brackets = true` turns it on).
; Neovim's rainbow-delimiters.nvim reads the same capture names from a
; `rainbow-delimiters` query it can be pointed at. The names are the
; convention both share; a consumer that knows neither ignores the
; file.

[
  (source_file)
  (type_signature)
  (function_definition)
  (data_declaration)
  (type_parameters)
  (data_constructor)
  (macro_declaration)
  (macro_rule)
  (macro_pattern_form)
  (struct_declaration)
  (field_declaration)
  (type_alias)
  (import)
  (effect_declaration)
  (effect_operation)
  (extern_declaration)
  (extern_item)
  (extern_clause)
  (removed_form)
  (unit_type)
  (type_constructor)
  (function_type)
  (list_type)
  (tuple_type)
  (pointer_type)
  (effect_type)
  (syntax_binders_pattern)
  (parenthesized_pattern)
  (constructor_pattern)
  (tuple_pattern)
  (list_pattern)
  (lambda)
  (let_expression)
  (let_binding)
  (if_expression)
  (while_expression)
  (set_expression)
  (cond_expression)
  (cond_clause)
  (match_expression)
  (match_arm)
  (syntax_for_arm)
  (syntax_join_name)
  (syntax_for_declaration)
  (handle_expression)
  (effect_list)
  (alloc_expression)
  (sizeof_expression)
  (alignof_expression)
  (cast_expression)
  (struct_construction)
  (block)
  (list_literal)
  (application)
] @rainbow.scope

[
  "(" ")"
  "[" "]"
  "{" "}"
] @rainbow.bracket
