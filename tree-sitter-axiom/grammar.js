/**
 * Tree-sitter grammar for Axiom.
 *
 * The reference for every rule here is the compiler in this repository,
 * not a description of it: keyword spellings come from
 * `self_host/lexer.ax`, declaration and expression shapes from
 * `self_host/parser.ax`. Where the two could drift, the corpus in
 * `test/corpus/` is what catches it - it is parsed by both this grammar
 * and the real compiler in `scripts/check-tree-sitter.sh`.
 *
 * ## Why this grammar is deliberately permissive
 *
 * Axiom is an S-expression language, so almost every form is
 * `( head . rest )`. A grammar could reject `(if a)` for having too few
 * operands, and a compiler must. An editor grammar should not, because
 * the input it sees is nearly always mid-edit and therefore incomplete;
 * a grammar that fails on incomplete input produces an ERROR node that
 * swallows the rest of the file, and highlighting collapses exactly when
 * the author most needs it.
 *
 * So the arity rules here are minimums, not exact counts. `(if)` parses
 * as an `if_expression` with no operands. The compiler reports `AX2001`
 * for it, which is the right division of labour: this grammar's job is to
 * keep producing a usable tree, and the compiler's job is to be strict.
 *
 * ## Identifiers, and why `token` appears where it does
 *
 * The lexer's identifier rule is unusual and is faithfully reproduced
 * below: an identifier may be a run of operator characters
 * (`+`, `<=`, `>>=`), or a name, but not a name with operator characters
 * glued into the middle unless they are contiguous. Because operators are
 * ordinary identifiers rather than reserved punctuation, `+` in `(+ 1 2)`
 * is lexically an identifier in head position and nothing more - there is
 * no operator precedence to encode, which is most of why this grammar is
 * as short as it is.
 */

// Characters the lexer treats as operator constituents.
// Source: `isIdentStart`/`isIdentChar` in self_host/lexer.ax.
const OPERATOR_CHAR = /[+\-*\/%^=<>!&|.?~@]/;

// Built-in type names, which the lexer tokenises as distinct keywords
// rather than identifiers. They are listed so an editor can highlight
// `Int` differently from a user-defined type, which is the only reason
// the distinction matters outside the compiler.
const BUILTIN_TYPES = [
  'Int', 'Integer', 'Float', 'Double', 'Bool', 'Char', 'String',
  'Any', 'Void',
  'I8', 'I16', 'I32', 'I64', 'I128', 'Isize',
  'U8', 'U16', 'U32', 'U64', 'U128', 'Usize',
  'F32', 'F64',
];

// Effect names, likewise keywords in the lexer.
const EFFECT_NAMES = ['Pure', 'IO', 'Mut', 'Div'];

module.exports = grammar({
  name: 'axiom',

  extras: $ => [
    /\s/,
    $.axtag,
    $.comment,
    $.block_comment,
  ],

  // `#| ... |#` nests, and a nesting delimiter is not a token any
  // regular expression can describe. `src/scanner.c` reproduces the
  // compiler's `skipBlockComment` loop instead of approximating it -
  // see the comment at the top of that file for the input where an
  // approximation and the compiler disagree.
  externals: $ => [
    $.block_comment,
  ],

  // The word token must be the identifier rule itself, not a separate
  // "looks like a word" token.
  //
  // This was wrong in the first version of this grammar, with `word` set to
  // a private `_word` rule that `identifier` did not reduce to, and the
  // symptom was baffling out of proportion to the cause: `(g x)` failed to
  // parse while `(f x)` in a function definition succeeded. Keyword
  // extraction works by lexing the word token and comparing the result
  // against the keyword list, so when the word token is not the token the
  // grammar actually expects in identifier position, every identifier that
  // is not also a keyword becomes unlexable in exactly the states where
  // keywords are possible - which is every parenthesised form.
  word: $ => $.identifier,

  // `(struct Name ...)` is a declaration when its body is
  // `(field : Type)` items and a construction when its body is
  // expressions - a distinction that only becomes visible at the `:`,
  // which is past the point where an LR parser has to commit.
  //
  // This is the one place a declared conflict is the right answer rather
  // than a workaround. The alternatives the generator offers are a
  // precedence on one rule or the other, and both would be assertions
  // that one reading is always preferred, which is false: `(struct Point
  // (x : Int))` and `(struct Point 1 2)` are both correct and neither is
  // more likely. Letting the GLR parser carry both interpretations until
  // the body decides is exactly the mechanism for that. For the genuinely
  // ambiguous empty body `(struct Point)`, rule order decides, and either
  // answer highlights identically.
  conflicts: $ => [
    [$.struct_declaration, $.struct_construction],
    // The same ambiguity one level down: in `(struct Point () ...)` the
    // `()` is an empty type parameter list if this is a declaration and an
    // empty-tuple argument if it is a construction. It has to be listed
    // separately because the generator reports conflicts between the
    // specific rules that collide, not between their parents.
    [$.type_parameters, $.application],
    // `(struct Point (x : Int))`: after `struct Point`, a `(` followed by
    // a name begins a type parameter list *and* a field declaration, and
    // the two only diverge at the `:` two tokens later. As long as the
    // parameters were the `type_variable` *token*, the choice fell to the
    // lexer, which cannot see that far - so every `struct` with fields
    // failed to parse, and with them most of `self_host/`. Spelling the
    // parameters as `identifier` (see `type_parameters`) moves the
    // decision to the parser, and this declares the ambiguity it then
    // has to resolve: `(struct P (x))` is a parameter list or a
    // construction whose argument is `(x)`.
    [$.type_parameters, $._expression],
    // `(struct S (msg String))`: with the `:` gone, a field declaration
    // and an application of `msg` to `String` are the same tokens, and
    // they diverge nowhere - the whole point of the `:` is that it is
    // what separates them, which is why the compiler refuses the form
    // (AX3056) rather than choosing a reading. The grammar still has to
    // PARSE it, because the fixture pinning that refusal is a `.ax`
    // file like any other and check-tree-sitter parses all of them. So
    // the ambiguity is declared and rule order decides, exactly as it
    // does for the empty `(struct Point)` body above: either answer
    // highlights identically, and neither is a claim about which
    // reading is right.
    [$.field_declaration, $._expression],
    // And the same three-way, because a `(` after a struct's name may
    // still be opening the type-parameter list: `(struct S (msg
    // String))` is a parameter list, a field declaration and an
    // application until the body ends.
    [$.type_parameters, $.field_declaration, $._expression],
    [$.type_parameters, $.field_declaration],
    // `(handle body (foo) handler)`: is `(foo)` a one-element custom effect
    // list, or is it an application that serves as the handler? Nothing in
    // the form settles it, and the language itself is ambiguous here -
    // `parse_handle` in the compiler resolves it greedily, treating any `(`
    // immediately after the body as the effect list. Declaring the conflict
    // lets the GLR parser reach the same answer through rule order instead
    // of a precedence that would claim the readings differ in likelihood.
    //
    // It took three attempts to state this in a form the generator accepts,
    // and the reason is worth knowing: a conflict can only be declared
    // between rules the generator can name. `[handle_expression,
    // application]` was rejected because the collision is really between
    // whatever `identifier` reduces to, and while `_expression` is hidden it
    // is still a nameable symbol, `_effect` as a hidden alias was not - so
    // `effect` had to become a concrete node first.
    [$.effect, $._expression],
  ],

  supertypes: $ => [
    $._declaration,
    $._expression,
    $._type,
    $._pattern,
    $._literal,
  ],

  rules: {
    source_file: $ => repeat($._form),

    // A file is a sequence of declarations, but an editor also has to
    // cope with a bare expression at top level (someone pasting a
    // snippet, or a REPL transcript). Accepting both keeps the tree
    // useful in those cases; the compiler rejects the second.
    _form: $ => choice(
      $._declaration,
      $._expression,
    ),

    // -----------------------------------------------------------------
    // Trivia
    // -----------------------------------------------------------------

    // AXTAGs are listed in `extras` alongside comments because they may
    // appear above any declaration and the grammar should not have to
    // thread an optional tag list through every declaration rule. They
    // are still a named node, so a query can find them, and an editor can
    // highlight `;@axiom:effect(io)` as metadata rather than as a comment.
    //
    // Matched before `comment` matters: both start with `;`, and
    // tree-sitter's lexer prefers the longer match, but being explicit
    // about the `@axiom:` prefix keeps the two from being ambiguous at
    // all.
    axtag: _ => token(seq(';@axiom:', /[^\r\n]*/)),

    comment: _ => token(seq(';', /[^\r\n]*/)),

    // `block_comment` has no rule here on purpose: it is produced only
    // by `src/scanner.c`. Giving it a body as well would hand the
    // generated lexer a second, non-nesting way to match one - taken
    // during error recovery, where it would close the comment at the
    // first `|#` and disagree with the compiler exactly when the input
    // is already confusing.

    // -----------------------------------------------------------------
    // Declarations
    // -----------------------------------------------------------------

    // `type_signature` is deliberately absent from this list even though
    // `(:: add (-> Int Int))` is a declaration. Since one rule now covers
    // both the top-level and inline spellings, listing it under both
    // `_declaration` and `_expression` makes `_form` ambiguous for a
    // reason that has nothing to do with the language - the two paths
    // produce an identical node. It is reachable at top level through
    // `_expression`, and queries match on the node, not on which supertype
    // it arrived under.
    _declaration: $ => choice(
      $.function_definition,
      $.data_declaration,
      $.struct_declaration,
      $.type_alias,
      $.trait_declaration,
      $.impl_declaration,
      $.import,
      $.effect_declaration,
      $.extern_declaration,
      $.macro_declaration,
      $.syntax_for_declaration,
    ),

    // `(:: subject Type)`
    //
    // One rule covers both the top-level signature `(:: add (-> Int Int))`
    // and the inline ascription `(:: (f x) Int)`, because they are not
    // merely similar - they are the same syntax. An earlier version of
    // this grammar had them as two rules and tree-sitter rejected it with
    // an unresolvable conflict on `'(' '::' identifier . '('`, which was
    // correct: nothing local distinguishes them. Splitting them would have
    // required a precedence hack asserting a difference that does not
    // exist.
    //
    // A query can still tell them apart when it matters, because a
    // top-level signature's subject is always a bare identifier:
    // `(type_signature subject: (identifier))`.
    type_signature: $ => seq(
      '(', optional(field('visibility', 'pub')), '::',
      // `syntax_join_name` FIRST: `(:: (syntax/join wrap nm) ...)` is a
      // joined declaration name inside a template, and `_expression`
      // would take it as an ordinary application of `syntax/join` to
      // two arguments - a tree that says the wrong thing about the
      // same bytes.
      field('subject', choice($.syntax_join_name, $._expression)),
      field('type', $._type), ')',
    ),

    // `(fn (name params...) body)` or `(define name body)`.
    //
    // Both spellings exist and `fn` is the modern one; they are the same
    // node here because an editor has no reason to distinguish them and
    // every reason to highlight them identically.
    function_definition: $ => seq(
      '(',
      optional(field('visibility', 'pub')), choice('fn', 'define'),
      choice(
        // `(fn (name p1 p2) body)` - the parenthesised form, which is
        // also how a nullary function is written: `(fn (main) ...)`.
        // The name may also be the query form `(syntax/join a b)`
        // (MAC-CAP-5), standing in for the identifier a declaration
        // macro computes at instantiation.
        seq('(', field('name', choice($.identifier, $.syntax_join_name)),
            repeat(field('parameter', $._pattern)), ')'),
        // `(fn name body)` - a named constant.
        field('name', $.identifier),
      ),
      repeat(field('body', $._expression)),
      ')',
    ),

    // `(data Name (tyvars...) (Ctor field...)...)`
    // The name may also be `(syntax/join a b)`, since `data` became a
    // declaration-macro template kind (MAC-CAP-7/8): a generated type
    // is named the same way a generated function is.
    data_declaration: $ => seq(
      '(', optional(field('visibility', 'pub')), 'data',
      field('name', choice($.identifier, $.syntax_join_name)),
      optional(field('type_parameters', $._data_type_parameters)),
      repeat(field('constructor', $.data_constructor)),
      ')',
    ),

    // Type parameters hold only lowercase names and constructors only
    // uppercase ones, which is not a stylistic convention here but the
    // rule the compiler uses: `looks_like_tyvar_list` in
    // `self_host/parser.ax` accepts a parenthesised group as a type
    // parameter list exactly when every name in it starts lowercase.
    //
    // Encoding that makes `(data Maybe (a) (Nothing) (Just a))`
    // unambiguous. Without it, `(a)` and `(Nothing)` are both
    // `'(' identifier ')'` and the generator rejects the grammar - and the
    // available workarounds, a precedence or a declared conflict, would
    // both guess at something the compiler decides by case.
    // The parameters are spelled with `identifier` and aliased, not with
    // the `type_variable` token, so that `(` + name is the *same* token
    // sequence whether this turns out to be a type parameter list or a
    // field declaration. As two distinct tokens the choice fell to the
    // lexer, which cannot see the `:` two tokens ahead that actually
    // decides it - so `(struct Point (x : Int))` committed to a type
    // parameter list and failed on the `:`. One token lets the declared
    // conflict below defer the decision to the parser, which can.
    type_parameters: $ => seq('(', repeat(alias($.identifier, $.type_variable)), ')'),

    // A `data` declaration's parameters, which may also be the bare `a`
    // that `fmt` emits: `format_type_vars` parenthesises a list and
    // prints a single one on its own, so `(data Tree (a) ...)` formats
    // to `(data Tree a ...)`. Only the parenthesised form was described
    // here, so the grammar rejected the output of this repository's own
    // formatter - unnoticed, because every `data` in the corpus is
    // written with the parens and the corpus is not stored formatted.
    //
    // `struct` deliberately does not get the bare form either, even
    // though the layout modifiers that made it ambiguous - `repr(C)`,
    // `packed`, `align(8)` - are gone. No `struct` in the corpus is
    // written that way, and widening the rule is a change to what the
    // grammar accepts rather than to what it stops rejecting.
    _data_type_parameters: $ => choice(
      $.type_parameters,
      alias($.type_variable, $.type_parameters),
    ),

    // `(Just a)` or `(Circle { r : Int })`. The braced form is a struct
    // variant: fields are named, and a pattern may then bind them by
    // name and in any order.
    // A constructor's name is a NAME POSITION too, so a template may
    // spell it `(syntax/join Off N)` - which is what lets two
    // invocations of one macro generate two distinct types rather
    // than colliding on a fixed constructor name.
    data_constructor: $ => seq(
      '(',
      field('name', choice($.constructor_identifier, $.syntax_join_name)),
      choice(
        repeat(field('field', $._type)),
        seq('{', repeat(seq(field('field', $.named_field), optional(','))), '}'),
      ),
      ')',
    ),

    named_field: $ => seq(field('name', $.identifier), ':', field('type', $._type)),

    // `(macro (name params...) body)` - pattern-free template macros,
    // which is all `stdlib/Pre.ax` uses.
    // Two forms, split by one token of lookahead after `macro`: a
    // paren opens the HEAD-LIST (expression-template) form, an
    // identifier the RULE form (macro-system.md MAC-LANG-14), whose
    // template is DECLARATIONS - including further declaration-macro
    // invocations, which parse as top-level calls. The rule form takes
    // ONE OR MORE rules since 2026-08-15, selected by arity.
    macro_declaration: $ => choice(
      seq(
        '(', optional(field('visibility', 'pub')), 'macro',
        '(', field('name', $.identifier), repeat(field('parameter', $.identifier)), ')',
        repeat(field('body', $._expression)),
        ')',
      ),
      seq(
        '(', optional(field('visibility', 'pub')), 'macro',
        field('name', $.identifier),
        repeat1(field('rule', $.macro_rule)),
        ')',
      ),
    ),

    macro_rule: $ => seq(
      '(',
      '(', field('rule_name', $.identifier), repeat(field('parameter', $._macro_pattern)), ')',
      repeat(field('template', $._form)),
      ')',
    ),

    // MAC-LANG-15: a rule's parameter is a PATTERN, not only a name.
    // Four kinds, matching `parseMacroPat` (self_host/parser.ax): an
    // identifier (a binder, or `_` binding nothing), a literal, or a
    // parenthesised form of patterns.
    //
    // Hidden, so an all-identifier rule - which is every rule written
    // before 2026-08-16 - still parses to `(identifier)` directly
    // under `macro_rule` and no existing corpus tree renests.
    //
    // `boolean_literal` is deliberately NOT here: `true` and `false`
    // are ordinary identifiers to the compiler's lexer, so a pattern
    // spelling one binds it rather than matching it, and a grammar
    // that called it a literal would describe a language this
    // compiler does not have.
    _macro_pattern: $ => choice(
      $.identifier,
      $.integer_literal,
      $.float_literal,
      $.character_literal,
      $.string_literal,
      $.macro_pattern_form,
      $.ellipsis,
    ),

    macro_pattern_form: $ => seq('(', repeat1($._macro_pattern), ')'),

    // MAC-LANG-16. `...` is an ordinary IDENTIFIER to the compiler's
    // lexer - three dots, one token, no new token kind - which is what
    // let that rule's token half be one implementation rather than the
    // four it predicted. This grammar's identifier rule already
    // admitted it for the same reason, so a named node here is a
    // FIDELITY change and not a fix: it marks the element before it as
    // repeating, where an `(identifier)` said only that something was
    // spelled with dots.
    ellipsis: _ => '...',

    // The `deriving_clause` rule was DELETED on 2026-08-14, the day
    // the compiler started refusing the clause (AX2004, MAC-CAP-9):
    // a grammar that accepts what the compiler refuses is the drift
    // this file's history keeps recording, and an AST arm without a
    // producer is dead syntax.

    // `(struct Name (field : Type)...)`
    //
    // The C layout modifiers `packed`, `repr(C)` and `align(N)` used to
    // sit between the name and the fields. The compiler's parser never
    // accepted any of them - all three are `AX2001` - so the only
    // programs this grammar described there were programs that do not
    // compile, and C layout means nothing in a language that links no C.
    // The type parameter list carries a DYNAMIC precedence, and it has
    // to. `(struct ShowOf (a) (render : (-> a String)))` gives the GLR
    // parser two readings of `(a)`: a parameter list, or a
    // `field_declaration` whose type is missing - a shape the grammar
    // deliberately parses so the AX3056 fixture can be a `.ax` file
    // like any other. Both survive to the end of the declaration, so
    // rule order decided, and it decided FIELD - the grammar accepted
    // the text and disagreed with the compiler about what it meant.
    //
    // The compiler's rule is the `:`: a group whose second token is a
    // colon is a field, and one whose second token is not is a
    // parameter list (`structGroupIsTyParams` in
    // `self_host/parser.ax`). Precedence expresses exactly that here,
    // because `(x : Int)` cannot match `type_parameters` at all - the
    // colon excludes it - so raising this rule only settles the case
    // where the two genuinely collide, which is the case the compiler
    // decides the same way.
    struct_declaration: $ => seq(
      '(', optional(field('visibility', 'pub')), 'struct',
      field('name', choice($.identifier, $.syntax_join_name)),
      optional(field('type_parameters', prec.dynamic(1, $.type_parameters))),
      repeat(field('field', $.field_declaration)),
      ')',
    ),

    // `(name : Type)` with an optional `mut` before the name. The
    // parser also reads three shapes it should not - `(name Type)` with
    // no colon, a `:` whose right side is not a type, and a bare
    // `(name)` - and the checker refuses all three as AX3056, since a
    // field type it cannot classify silently leaves the block's
    // reference map. The grammar follows the parser here for the reason
    // `effect_operation` does: the fixture that pins the code has to
    // parse, and the refusal is the checker's to make, not the
    // grammar's. `(name)` alone is left out - after a struct's name it
    // is a type-parameter list, which is the reading the formatter
    // takes and this rule must not fight.
    field_declaration: $ => seq(
      '(',
      optional('mut'),
      field('name', $.identifier),
      optional(choice(
        seq(':', field('type', choice($._type, $._literal))),
        field('type', $._type),
      )),
      ')',
    ),

    // `(type Name (tyvars...) = Type)`. The `=` is optional in the
    // parser, so it is optional here.
    type_alias: $ => seq(
      '(', optional(field('visibility', 'pub')), 'type',
      field('name', choice($.identifier, $.syntax_join_name)),
      optional(field('type_parameters', $.type_parameters)),
      optional('='),
      field('target', $._type),
      ')',
    ),

    // There is no `newtype`. The compiler has never had the keyword -
    // `(newtype ...)` answers AX3027, "neither a declaration keyword nor
    // a visible macro" - and docs/error-model.md B3 records the
    // reference's row for it as drift that was deleted rather than
    // built. This grammar carried a `newtype_declaration` rule for as
    // long as that row existed and for a week after, which is the
    // failure the header of scripts/check-tree-sitter.sh names: an
    // editor highlighting as valid a form the compiler refuses. The
    // corpus sweep could not catch it, because no `.ax` file in the
    // repository spells the keyword - a rule that matches nothing is
    // invisible to a check that parses everything.

    // `(trait (Name tv) (supertraits) (effects) where (methods))`
    //
    // This used to describe a different language: methods were each
    // parenthesised and `where` introduced a *default body* inside one.
    // The compiler's parser reads a flat `name :: type` sequence inside a
    // single `where ( ... )` group, with optional supertrait and effect
    // groups before it. The grammar accepted no real trait at all, and
    // nothing noticed because no `.ax` file in the repository declares
    // one - the same corpus-shaped blind spot that hid the formatter's
    // trait bugs.
    trait_declaration: $ => seq(
      '(', optional(field('visibility', 'pub')), 'trait',
      '(', field('name', $.identifier), optional(field('type_parameter', $.identifier)), ')',
      repeat(field('group', $.paren_group)),
      optional(seq('where', '(', repeat(field('member', $.trait_method)), ')')),
      ')',
    ),

    // A trait method: `name :: type [= default] [(effects)]`, with no
    // parentheses of its own.
    trait_method: $ => seq(
      field('name', $.identifier),
      '::',
      field('type', $._type),
      optional(seq('=', field('default', $._expression))),
      optional(field('effects', $.paren_group)),
    ),

    // A parenthesised list of identifiers or types: a supertrait list or
    // an effect list. The compiler's parser distinguishes the two only by
    // position, and both are spelled the same way, so the grammar - which
    // exists for highlighting and structural selection - does not try to
    // tell them apart either.
    paren_group: $ => seq('(', repeat(choice($.builtin_effect, $._type)), ')'),

    effect_clause: $ => seq('(', 'effect', repeat($.effect), ')'),

    impl_declaration: $ => seq(
      '(', optional(field('visibility', 'pub')), 'impl',
      '(', field('trait', $.identifier), field('type', $._type), ')',
      optional(field('effects', $.paren_group)),
      optional(seq('where', '(', repeat(field('member', $.impl_method)), ')')),
      ')',
    ),

    impl_method: $ => seq(
      '(',
      field('name', $.identifier),
      repeat(field('body', $._expression)),
      ')',
    ),

    // `(import Mod.Sub)` or `(import Mod.Sub (a b))`
    import: $ => seq(
      '(', optional(field('visibility', 'pub')), 'import',
      field('module', $.module_path),
      optional(seq('(', repeat(field('name', $.identifier)), ')')),
      ')',
    ),

    // The lexer produces `Mod`, `.`, `Sub` as separate tokens, but `.` is
    // an operator character, so `Mod.Sub` is lexed as a *single*
    // identifier token. Reproducing that here rather than as three nodes
    // keeps the tree agreeing with the compiler's view.
    module_path: _ => token(/[A-Za-z_][A-Za-z0-9_']*(\.[A-Za-z_][A-Za-z0-9_']*)*/),

    effect_declaration: $ => seq(
      '(', optional(field('visibility', 'pub')), 'effect',
      field('name', choice($.identifier, $.syntax_join_name)),
      repeat(field('operation', $.effect_operation)),
      ')',
    ),

    // An operation is `(name :: Type)`; the parser also reads a bare
    // `(name)` (the checker refuses it, AX3055) and a `::` whose right
    // side it cannot read as a type (the same field left at 0), so the
    // grammar accepts a literal there too - the fixture that pins
    // AX3055 spells `(notAType :: 5)`. The grammar follows the parser;
    // the refusal is the checker's.
    effect_operation: $ => seq(
      '(', field('name', $.identifier),
      optional(seq('::', field('type', choice($._type, $._literal)))),
      ')',
    ),

    // `(extern "lib" (name :: Type (symbol "s")) ...)` - the Rust FFI
    // binding block (docs/ffi.md).
    //
    // Shaped like `effect_declaration` directly above, because the two
    // forms are the same shape: a header followed by a list of typed
    // callables. The difference is that the header is a STRING (the
    // library) rather than an identifier, and each item carries a
    // clause tail.
    //
    // `extern` is a distinct token from `foreign` below and always will
    // be: `foreign` stays a removed construct reporting AX2004, so old
    // source keeps getting migration advice instead of being reparsed
    // as the new form.
    extern_declaration: $ => seq(
      '(', optional(field('visibility', 'pub')), 'extern',
      field('library', $.string_literal),
      repeat(field('item', $.extern_item)),
      ')',
    ),

    extern_item: $ => seq(
      '(', field('name', $.identifier), '::', field('type', $._type),
      repeat(field('clause', $.extern_clause)),
      ')',
    ),

    // The clause tail. `symbol` is the only clause v1 defines; the rule
    // takes any `(ident ...)` so a future clause parses as a clause
    // rather than as an ERROR region.
    extern_clause: $ => seq(
      '(', field('key', $.identifier), repeat($._expression), ')',
    ),


    // -----------------------------------------------------------------
    // Removed constructs
    //
    // `union` and `foreign` are no longer part of the language but
    // remain reserved words, and the compiler reports `AX2004` for
    // them. `region` was the third until 2026-09-03; it is an expression
    // again (`region_expression` below) and left this list with its
    // false migration advice. They are in the grammar so an editor can mark the whole form
    // as an error region with a useful name, instead of showing an
    // anonymous ERROR node whose extent depends on where the recovery
    // happened to land.
    // -----------------------------------------------------------------

    // One permissive rule, for the reason `type_signature` is one: a
    // dead form's body has to be swallowed whole, and `(union Value (i :
    // Int))` sat in declaration position. It accepted `region`'s
    // name-plus-body too while `region` was dead, and the body still
    // accepts expressions beside field declarations so that an old
    // `union` with an expression in it is one bounded node rather than
    // a cascade. Accepting bare types as well was tried and is
    // ambiguous - `[]` is both an empty `list_type` and an empty
    // `list_literal`, with nothing in a dead form to disambiguate them -
    // and it is unnecessary, because the only types that appeared in
    // these forms were inside field declarations.
    //
    // Consuming the body at all is the point: an old `union` must be
    // swallowed whole, or recovery ends mid-declaration and the trailing
    // fields get reinterpreted as top-level forms, turning one dead
    // declaration into a cascade of unrelated errors.
    // `foreign` gets a branch of its own rather than joining the
    // permissive body above, because its tail - `name :: Type = "sym"` -
    // is neither a field declaration nor an expression, and a body that
    // could not swallow it would leave the `::` to start a cascade. The
    // two branches are distinguished by their keyword token, which is a
    // decision this grammar can make one token in.
    removed_form: $ => choice(
      seq(
        '(',
        field('keyword', $.removed_keyword),
        repeat(choice($.field_declaration, $._expression)),
        ')',
      ),
      seq(
        '(',
        field('keyword', alias($._removed_foreign, $.removed_keyword)),
        field('name', $.identifier),
        '::',
        field('type', $._type),
        '=',
        field('symbol', $.string_literal),
        ')',
      ),
    ),

    removed_keyword: _ => 'union',
    _removed_foreign: _ => 'foreign',

    // -----------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------

    _type: $ => choice(
      $.builtin_type,
      $.unit_type,
      $.type_variable,
      $.type_constructor,
      $.region_type,
      $.function_type,
      $.list_type,
      $.tuple_type,
      $.pointer_type,
      $.effect_type,
      // `(syntax/join a b)` where a TYPE stands - a `type` template
      // names its alias with a join, and the signature beside it has
      // to be able to write that name (MAC-CAP-8).
      $.syntax_join_name,
    ),

    builtin_type: _ => choice(...BUILTIN_TYPES),

    // `()` - two tokens, not one.
    //
    // As `token(seq('(', ')'))` this was a single lexeme, and it silently
    // broke `(type StringList () = [String])`: the empty type parameter
    // list is also `()`, but `type_parameters` is built from separate `'('`
    // and `')'` tokens, so the lexer handed it a `unit_type` it had no rule
    // for. The compiler accepts that program - `looks_like_tyvar_list`
    // returns true for an empty group - so the grammar has to as well.
    unit_type: $ => seq('(', ')'),

    // A lowercase name in type position is a variable (`a`), an uppercase
    // one is a constructor (`Maybe`). That is the compiler's rule, and
    // encoding it here is what lets an editor colour the two differently.
    type_variable: _ => token(/[a-z][A-Za-z0-9_']*/),

    // There is no general "parenthesised type" rule, and that is not an
    // omission: `parseType` in `self_host/parser.ax` accepts a
    // parenthesised group in type position only when it is headed by `->`,
    // `*`, a comma-separated tuple, `()`, or a *capitalised*
    // name. `(a)` for a lowercase type variable is not valid Axiom, so it
    // is not valid here.
    //
    // Adding one anyway was tried and made the grammar ambiguous in two
    // places at once - `(a)` as a parenthesised variable versus a type
    // parameter list, and `(Maybe)` as a parenthesised constructor versus a
    // zero-argument application - both of which vanish once the rule is
    // dropped. `repeat` rather than `repeat1` then matches the compiler,
    // which does allow a zero-argument application.
    type_constructor: $ => choice(
      $.constructor_identifier,
      seq('(', field('name', $.constructor_identifier), repeat(field('argument', $._type)),
          optional(field('region', $.region_annotation)), ')'),
    ),

    // `(Str @r)`, `(Vec Int @r)`, `(String @r)`, `(a @r)` - a REGION
    // ANNOTATION is the last thing inside a type's parentheses
    // (`parseTypeAtomsRgn` in self_host/parser.ax; stage S3 of
    // docs/memory-model-v2-design.md). On a constructor application it
    // is the optional trailing field above; a keyword type or a type
    // variable takes it through this rule, which is the one place the
    // grammar admits a parenthesised variable - `(a @r)` is valid Axiom
    // because the annotation is what the parentheses are for. `@` alone
    // is still not a token: the compiler refuses it as AX1001.
    region_type: $ => seq(
      '(', field('type', choice($.builtin_type, $.type_variable, $.function_type, $.list_type)),
      field('region', $.region_annotation), ')',
    ),

    region_annotation: _ => token(/@[a-z][A-Za-z0-9_']*/),

    // `(-> A B C)` - n-ary in the source, curried in the compiler.
    function_type: $ => seq('(', '->', repeat(field('operand', $._type)), ')'),

    // `[T]`
    list_type: $ => seq('[', optional(field('element', $._type)), ']'),

    // `(A , B)` - the parser accepts a comma-separated type list.
    tuple_type: $ => seq(
      '(', field('element', $._type), repeat1(seq(',', field('element', $._type))), ')',
    ),

    // `(* T)` or `(* mut T)`
    pointer_type: $ => seq('(', '*', optional('mut'), field('target', $._type), ')'),

    effect_type: $ => seq(
      '(', field('target', $._type), '!', repeat(field('effect', $.effect)), ')',
    ),

    // A concrete node, not a hidden alias. As a hidden rule this was the
    // unresolvable half of the handle-form ambiguity: at `'(' identifier .`
    // the parser must reduce the identifier either to an effect or to an
    // expression, and a conflict can only be declared between named rules.
    effect: $ => choice($.builtin_effect, $.identifier),

    builtin_effect: _ => choice(...EFFECT_NAMES),

    // -----------------------------------------------------------------
    // Patterns
    // -----------------------------------------------------------------

    _pattern: $ => choice(
      $.wildcard_pattern,
      $._literal,
      $.identifier,
      $.constructor_pattern,
      $.parenthesized_pattern,
      $.tuple_pattern,
      $.list_pattern,
      $.syntax_binders_pattern,
    ),

    // `(syntax/binders C x)` standing where a pattern ARGUMENT
    // stands (MAC-CAP-5): arity-of-C binder names spliced by the
    // expander during template instantiation.
    syntax_binders_pattern: $ => seq(
      '(', 'syntax/binders',
      field('constructor', $.identifier), field('prefix', $.identifier),
      ')',
    ),

    wildcard_pattern: _ => '_',

    // `(true)`, `(false)`, `(1)`, `(_)`.
    //
    // A pattern in this language is PARSED as an expression and only
    // then read as a pattern (`parseArmPattern` falls back to
    // `parseExpr`), so the nullary-constructor spelling `(Nil)` is
    // available to a literal too, and the compiler accepts it:
    //
    //   (match b ((true) 1) ((false) 0))
    //
    // is a complete, running program - `true` and `false` in pattern
    // position are literal TESTS, which `emitPattern` compares the
    // scrutinee against. This grammar modelled patterns structurally
    // and had no rule for the parenthesised form, so it reported an
    // ERROR on source the compiler runs.
    //
    // Found by `tests/selfhost/365-macro-pattern-literal.ax`, the
    // fixture written to pin a macro-hygiene bug about exactly these
    // two names. No file in the repository had used the form before
    // it, which is why 243 of 244 parsed and this did not - the same
    // sentence this project keeps writing.
    //
    // Unambiguous against `constructor_pattern`, which requires a
    // `constructor_identifier` (`[A-Z]...`): none of `true`, `false`,
    // a number or `_` can begin one.
    parenthesized_pattern: $ => seq(
      '(', field('pattern', choice($._literal, $.wildcard_pattern)), ')',
    ),

    // `(Cons h t)`, and nested: `(Cons h (Cons h2 t))`.
    // `(Just x)`, or the struct-variant form `(Rect { w = w, h })`.
    //
    // In the braced form a field may be bound explicitly (`w = pat`) or
    // punned (`w`, meaning `w = w`), the order need not match the
    // declaration, and a field the pattern does not name is simply not
    // bound.
    constructor_pattern: $ => seq(
      '(',
      field('constructor', $.constructor_identifier),
      choice(
        repeat(field('argument', $._pattern)),
        seq('{', repeat(seq(field('field', $.field_pattern), optional(','))), '}'),
      ),
      ')',
    ),

    field_pattern: $ => seq(
      field('name', $.identifier),
      optional(seq('=', field('pattern', $._pattern))),
    ),

    tuple_pattern: $ => seq(
      '(', field('element', $._pattern), repeat1(seq(',', field('element', $._pattern))), ')',
    ),

    list_pattern: $ => seq('[', repeat(field('element', $._pattern)), ']'),

    // -----------------------------------------------------------------
    // Expressions
    // -----------------------------------------------------------------

    _expression: $ => choice(
      $._literal,
      $.identifier,
      $.lambda,
      $.let_expression,
      $.qualified_identifier,
      $.if_expression,
      $.while_expression,
      $.for_expression,
      $.region_expression,
      $.parallel_expression,
      $.set_expression,
      $.cond_expression,
      $.match_expression,
      $.handle_expression,
      $.alloc_expression,
      $.sizeof_expression,
      $.alignof_expression,
      $.cast_expression,
      $.type_signature,
      $.struct_construction,
      $.block,
      $.list_literal,
      $.removed_form,
      // Application is last so that every special form gets first refusal
      // on the token after `(`. A head that is not a keyword falls through
      // to here, which is what makes `(+ 1 2)` and `(f x)` the same shape.
      $.application,
    ),

    lambda: $ => seq(
      '(', 'lambda',
      '(', repeat(field('parameter', $._pattern)), ')',
      repeat(field('body', $._expression)),
      ')',
    ),

    let_expression: $ => seq(
      '(', 'let',
      '(', repeat(field('binding', $.let_binding)), ')',
      repeat(field('body', $._expression)),
      ')',
    ),

    // `mut` marks the binding assignable by `set`. Optional, and
    // absent means immutable, which is the default in the language.
    let_binding: $ => seq(
      '(',
      optional(field('mutable', 'mut')),
      field('pattern', $._pattern),
      field('value', $._expression),
      ')',
    ),

    if_expression: $ => seq('(', 'if', repeat(field('operand', $._expression)), ')'),

    // `Mod::name`, and `Mod.Sub::name` - the dotted path is already a
    // single identifier token, because `.` continues an identifier.
    qualified_identifier: $ => prec(2, seq(
      field('module', $.identifier), '::', field('name', $.identifier),
    )),

    while_expression: $ => seq(
      '(', 'while',
      field('condition', $._expression),
      repeat(field('body', $._expression)),
      ')',
    ),

    // `(for i lo hi body)` and `(for x xs body)`, told apart by ARITY -
    // three operands after the binder is the range, two is the
    // container, and there is exactly one body expression in both
    // (`self_host/parser.ax`'s `parseForExpr`). The optional third
    // operand is what makes one rule cover both; a fourth is a parse
    // error in the compiler (AX2001,
    // `tests/diagnostics/625-for-shape.axbad`) and is simply not in this
    // grammar's language either.
    for_expression: $ => seq(
      '(', 'for',
      field('binder', $.identifier),
      field('operand', $._expression),
      field('operand', $._expression),
      optional(field('operand', $._expression)),
      ')',
    ),

    // `(region r body)` - a checked allocation scope, MM-RGN-1 of
    // docs/memory-model-v2-design.md (S2, 2026-09-03). The name is a
    // binder and the body is exactly one expression
    // (`self_host/parser.ax`'s `parseRegionExpr`); a second body is a
    // parse error in the compiler and is simply not in this grammar's
    // language either. `region` was a REMOVED keyword until this rule
    // existed - see `removed_form` above, which no longer names it.
    region_expression: $ => seq(
      '(', 'region',
      field('name', $.identifier),
      field('body', $._expression),
      ')',
    ),

    // `(parallel p ((a e1) (b e2) ...) body...)` - the region name, a
    // binding list of `(name expr)` pairs, one or more body expressions
    // (`self_host/parser.ax`'s `parseParallelExpr`). A binding is its own
    // node rather than a `let_binding` because `mut` is refused here -
    // the compiler makes it AX2001 (`tests/diagnostics/640-parallel-shape`)
    // and this grammar simply does not admit it.
    parallel_expression: $ => seq(
      '(', 'parallel',
      field('region', $.identifier),
      '(', repeat1(field('binding', $.parallel_binding)), ')',
      repeat1(field('body', $._expression)),
      ')',
    ),

    parallel_binding: $ => seq(
      '(', field('name', $.identifier), field('value', $._expression), ')',
    ),

    // The target is an identifier, not an expression: `set` names a
    // slot rather than computing a place. That covers the field form
    // `(set r.field v)` without a second alternative, because `.` is an
    // operator character the identifier token glues on - so `r.field`
    // arrives here as one identifier, exactly as a module path does.
    // The compiler's own lexer instead emits `.` as its own token and
    // the parser rebuilds the chain; only the spelling of the split
    // differs, not the set of programs accepted.
    set_expression: $ => seq(
      '(', 'set', field('target', $.identifier), field('value', $._expression), ')',
    ),

    cond_expression: $ => seq(
      '(', 'cond', repeat(field('clause', $.cond_clause)), ')',
    ),

    cond_clause: $ => seq(
      '(',
      choice(field('test', $._expression), field('else', 'else')),
      repeat(field('body', $._expression)),
      ')',
    ),

    match_expression: $ => seq(
      '(', 'match',
      field('scrutinee', $._expression),
      repeat(field('arm', choice($.match_arm, $.syntax_for_arm))),
      ')',
    ),

    match_arm: $ => seq(
      '(', field('pattern', $._pattern), repeat(field('body', $._expression)), ')',
    ),

    // `(syntax/for (C seq) arm...)` where an arm stands - the query
    // vocabulary's iteration form (macro-system.md MAC-CAP-5): one
    // template arm per element, spliced by the expander during
    // template instantiation. The head is a reserved spelling in this
    // position, matching the compiler's parseMatchArms.
    syntax_for_arm: $ => seq(
      '(', 'syntax/for',
      $._syntax_iter_binding,
      repeat1(field('arm', choice($.match_arm, $.syntax_for_arm))),
      ')',
    ),

    // One iteration variable bound to one sequence, or several zipped
    // in lockstep - the binding form `syntax/for` and `syntax/fold`
    // share (MAC-CAP-5). The two branches cannot collide: the single
    // form has an identifier where the parallel form has `(`, which
    // is the same one-token decision the compiler's `parseIterBinder`
    // makes off the parsed spine's head.
    //
    // HIDDEN (leading `_`), so the single form's tree is byte-for-byte
    // what it was before the parallel form existed: `binder` and
    // `sequence` stay fields of the iteration itself, and the parallel
    // form repeats them there. A named rule here would have renested
    // every existing tree - which the corpus tests caught, doing
    // exactly the job this gate's header claims for them.
    _syntax_iter_binding: $ => choice(
      seq('(', field('binder', $.identifier), field('sequence', $._expression), ')'),
      seq('(',
          repeat1(seq('(', field('binder', $.identifier),
                      field('sequence', $._expression), ')')),
          ')'),
    ),

    // `(syntax/join a b)` in a declaration NAME position - the joined
    // identifier phase D computes (`eq` + `Color` -> `eqColor`).
    // Either side may be a join of its own, which is how a generated
    // name carries more than two parts (`getPointX`).
    syntax_join_name: $ => seq(
      '(', 'syntax/join',
      field('left', choice($.identifier, $.syntax_join_name)),
      field('right', choice($.identifier, $.syntax_join_name)),
      ')',
    ),

    // `(syntax/for (f seq) decl...)` where a DECLARATION stands -
    // the iteration form one position up from syntax_for_arm,
    // matching the compiler's parseTopForm hook: the interior is
    // declarations, instantiated per element by phase D.
    syntax_for_declaration: $ => seq(
      '(', 'syntax/for',
      $._syntax_iter_binding,
      repeat1(field('declaration', $._form)),
      ')',
    ),

    handle_expression: $ => seq(
      '(', 'handle',
      field('body', $._expression),
      optional(field('effects', $.effect_list)),
      repeat(field('handler', $._expression)),
      ')',
    ),

    // `repeat1`, not `repeat`: with an empty list allowed, the `()` in
    // `(handle body () handler)` would be both an empty effect list and an
    // empty-tuple handler, and nothing later in the form decides which. An
    // empty effect list handles nothing, so requiring one effect costs
    // nothing and removes that ambiguity outright.
    //
    // The remaining ambiguity, `(foo)` as a one-element effect list versus
    // an application, is declared as a conflict below.
    effect_list: $ => seq('(', repeat1(field('effect', $.effect)), ')'),

    alloc_expression: $ => seq(
      '(', 'alloc', field('type', $._type), optional(field('count', $._expression)), ')',
    ),

    sizeof_expression: $ => seq('(', 'sizeof', field('type', $._type), ')'),

    alignof_expression: $ => seq('(', 'alignof', field('type', $._type), ')'),

    cast_expression: $ => seq(
      '(', 'cast', field('type', $._type), field('operand', $._expression), ')',
    ),

    struct_construction: $ => seq(
      '(', 'struct',
      field('name', $.identifier),
      repeat(field('argument', $._expression)),
      ')',
    ),

    // `{ e1 e2 ... }` - sequencing, value of the last expression.
    block: $ => seq('{', repeat(field('body', $._expression)), '}'),

    list_literal: $ => seq('[', repeat(field('element', $._expression)), ']'),

    // `(f x y)`. Also the empty tuple `()`, which the parser produces
    // from a bare `()` in expression position.
    application: $ => seq(
      '(', repeat(field('operand', $._expression)), ')',
    ),

    // -----------------------------------------------------------------
    // Literals and identifiers
    // -----------------------------------------------------------------

    _literal: $ => choice(
      $.integer_literal,
      $.float_literal,
      $.boolean_literal,
      $.character_literal,
      $.string_literal,
    ),

    // `_` is a digit separator in the lexer, so `1_000_000` is one token.
    // A leading `-` glued to a digit is part of the literal, as the
    // compiler's lexer treats it; `-` followed by anything else stays
    // an identifier, and `x-5` stays one identifier because the
    // identifier token is longer.
    integer_literal: _ => token(/-?[0-9][0-9_]*/),

    float_literal: _ => token(/-?[0-9][0-9_]*\.[0-9][0-9_]*([eE][+-]?[0-9]+)?/),

    boolean_literal: _ => choice('true', 'false'),

    // Escapes recognised by the lexer: \n \t \r \\ \" \' \0.
    // A bare quote is a character too: the lexer (`stepCharToken`)
    // reads quote + one character + quote and never asks what the
    // character is, so `'''` is the quote character - and
    // tests/stdlib/450-show-builtin.ax spells it that way.
    character_literal: _ => token(seq(
      "'",
      choice(/[^'\\]/, "'", seq('\\', /[ntr\\'"0]/)),
      "'",
    )),

    string_literal: _ => token(seq(
      '"',
      repeat(choice(/[^"\\]/, seq('\\', /[ntr\\'"0]/))),
      '"',
    )),

    // Visible, not hidden. As `_uppercase_identifier` it worked for
    // disambiguation but produced trees in which `(Nothing)` was a
    // `data_constructor` with no children at all - the name was an
    // invisible token, so no highlighting query or rename refactor could
    // reach it. A grammar whose nodes cannot be queried is not much use to
    // an editor, which is the only reason this grammar exists.
    //
    // The uppercase/lowercase split is the compiler's own rule: an
    // uppercase name is a type or data constructor, a lowercase one is a
    // type variable. Keeping them as distinct tokens is also what makes
    // `(data Maybe (a) (Nothing) ...)` unambiguous.
    constructor_identifier: _ => token(/[A-Z][A-Za-z0-9_']*/),

    // An identifier is either a name (possibly dotted, since `.` is an
    // operator character that the lexer glues on) or a bare run of
    // operator characters. Operators being identifiers is why this
    // grammar has no precedence table.
    identifier: _ => token(choice(
      /[A-Za-z_][A-Za-z0-9_']*([+\-*\/%^=<>!&|.?~@]+[A-Za-z0-9_']*)*/,
      new RegExp(OPERATOR_CHAR.source + '+'),
    )),
  },
});
