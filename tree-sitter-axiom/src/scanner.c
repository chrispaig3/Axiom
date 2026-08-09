// External scanner: `#| ... |#` block comments, which nest.
//
// WHY THIS IS C AND NOT A GRAMMAR RULE. Nesting is not expressible as a
// tree-sitter token, and the obvious rule spelling -
//
//   block_comment: $ => seq('#|', repeat(choice($.block_comment,
//                            /([^#|]|#[^|]|\|[^#])+/)), '|#')
//
// - disagrees with the compiler on inputs the compiler has an opinion
// about. `#| a||# |#` closes at the `|#` in `a||#` under the compiler's
// scanner (it tests `|` against the NEXT byte and advances one when that
// byte is not `#`, so the second `|` starts a fresh test), while the
// chunk regex consumes `||` as one match and leaves a `#` that cannot
// close anything. A grammar that drifts from the compiler is the failure
// `scripts/check-tree-sitter.sh` exists to prevent, so this reproduces
// `skipBlockComment` in `self_host/lexer.ax` byte for byte instead of
// approximating it.
//
// UNTERMINATED is not an error here either: the loop stops at EOF with
// the token still produced, which is what the compiler does (stage0's
// `consume_block_comment` returned `Ok` from the same shape) and what
// keeps a file whose tail is an unclosed comment out of the ERROR-node
// sweep for a reason the compiler does not share.

#include "tree_sitter/parser.h"

enum TokenType {
  BLOCK_COMMENT,
};

void *tree_sitter_axiom_external_scanner_create(void) { return NULL; }

void tree_sitter_axiom_external_scanner_destroy(void *payload) { (void)payload; }

// No state survives a token, so serialization is empty. Returning 0 is
// the documented spelling of "nothing to save", not a stub.
unsigned tree_sitter_axiom_external_scanner_serialize(void *payload, char *buffer) {
  (void)payload;
  (void)buffer;
  return 0;
}

void tree_sitter_axiom_external_scanner_deserialize(void *payload, const char *buffer,
                                                    unsigned length) {
  (void)payload;
  (void)buffer;
  (void)length;
}

bool tree_sitter_axiom_external_scanner_scan(void *payload, TSLexer *lexer,
                                             const bool *valid_symbols) {
  (void)payload;
  if (!valid_symbols[BLOCK_COMMENT]) return false;

  // An external token listed in `extras` is offered the position before
  // tree-sitter's own whitespace rule runs, so leading whitespace is
  // skipped here. `advance(lexer, true)` marks it skipped rather than
  // part of the token, which keeps the comment's span tight.
  while (lexer->lookahead == ' ' || lexer->lookahead == '\t' ||
         lexer->lookahead == '\n' || lexer->lookahead == '\r') {
    lexer->advance(lexer, true);
  }

  if (lexer->lookahead != '#') return false;
  lexer->advance(lexer, false);
  // A bare `#` is not a comment opener and not anything else either: the
  // compiler reports AX1001 on it. Refusing here leaves it to the
  // grammar, which has no rule for it, so it becomes an ERROR node -
  // the grammar's spelling of the same refusal.
  if (lexer->lookahead != '|') return false;
  lexer->advance(lexer, false);

  unsigned depth = 1;
  while (depth > 0) {
    if (lexer->eof(lexer)) break;
    if (lexer->lookahead == '#') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == '|') {
        lexer->advance(lexer, false);
        depth++;
      }
    } else if (lexer->lookahead == '|') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == '#') {
        lexer->advance(lexer, false);
        depth--;
      }
    } else {
      lexer->advance(lexer, false);
    }
  }

  lexer->result_symbol = BLOCK_COMMENT;
  return true;
}
