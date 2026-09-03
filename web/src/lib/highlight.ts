/**
 * A small syntax highlighter for Axiom.
 *
 * The capture names it emits are taken from
 * `tree-sitter-axiom/queries/highlights.scm`, which is the repository's
 * source of truth for "what syntactic role does this token play". That
 * file is deliberate about two things this implementation copies:
 *
 *  - AXTAGs (`;@axiom:...`) are captured as `@attribute`, NOT as a
 *    comment, because they are claims the compiler checks and rejects
 *    rather than notes to a human.
 *  - There is no blanket `constructor_identifier -> @type` rule, because
 *    the same token is a type in `(Maybe Int)` and a data constructor in
 *    `(Just a)`. Roles are resolved from position, exactly as the query
 *    file resolves them from `field(...)` labels in the grammar.
 *
 * The literal shapes (nesting `#| |#` block comments, `_` digit
 * separators, the escape set, the uppercase/lowercase identifier split)
 * come from `tree-sitter-axiom/grammar.js`.
 */

export type Capture =
  | 'comment'
  | 'attribute'
  | 'string'
  | 'string.hole'
  | 'character'
  | 'number'
  | 'boolean'
  | 'type'
  | 'type.builtin'
  | 'type.definition'
  | 'constructor'
  | 'function'
  | 'function.call'
  | 'function.method'
  | 'keyword'
  | 'keyword.function'
  | 'keyword.type'
  | 'keyword.conditional'
  | 'keyword.modifier'
  | 'module'
  | 'variable'
  | 'variable.parameter'
  | 'variable.member'
  | 'character.special'
  | 'punctuation.bracket'
  | 'punctuation.delimiter'
  | 'error'
  | 'text'

export interface Token {
  text: string
  capture: Capture
}

// grammar.js: BUILTIN_TYPES
const BUILTIN_TYPES = new Set([
  'Int', 'Integer', 'Float', 'Double', 'Bool', 'Char', 'String',
  'Any', 'Void', 'Unit',
  'I8', 'I16', 'I32', 'I64', 'I128', 'Isize',
  'U8', 'U16', 'U32', 'U64', 'U128', 'Usize',
  'F32', 'F64',
])

// The built-in effect row. grammar.js lists Pure/IO/Mut/Div; README.md's
// "Effects" status row names the set the checker infers over: IO, Pure,
// Alloc, Mut, Div.
const BUILTIN_EFFECTS = new Set(['Pure', 'IO', 'Alloc', 'Mut', 'Div'])

const KEYWORD_FUNCTION = new Set(['fn', 'define', 'lambda'])
const KEYWORD_TYPE = new Set(['data', 'struct', 'type', 'effect'])
const KEYWORD_CONDITIONAL = new Set(['if', 'cond', 'match', 'else'])
const KEYWORD_PLAIN = new Set([
  'let', 'handle', 'where', 'pub', 'import', 'set', 'while', 'extern', 'macro',
  // `region` returned on 2026-09-03 as a checked allocation scope
  // (docs/reference.md, Regions); it left REMOVED below the same day.
  'region',
])
const KEYWORD_MODIFIER = new Set(['alloc', 'sizeof', 'alignof', 'cast', 'mut'])

// Heads the parser refuses with AX2004. highlights.scm captures these as
// `@error` "because that is what the compiler reports".
// docs/reference.md, Keywords / Removed Keywords, is the list: union,
// foreign, deriving, linear, consume, begin, and — since 2026-08-31 —
// trait and impl. `region` was on it until 2026-09-03.
const REMOVED = new Set([
  'union', 'foreign', 'deriving',
  'linear', 'consume', 'begin', 'trait', 'impl',
])

const DELIMITERS = new Set(['::', '->', ':', '=', '!', ','])

type RawKind =
  | 'open' | 'close' | 'atom' | 'string' | 'char'
  | 'comment' | 'axtag' | 'space'

interface Raw {
  kind: RawKind
  text: string
}

const isSpace = (c: string) => c === ' ' || c === '\t' || c === '\n' || c === '\r'
const isBracket = (c: string) => '()[]{}'.includes(c)

function scan(src: string): Raw[] {
  const out: Raw[] = []
  let i = 0
  const n = src.length

  while (i < n) {
    const c = src[i] as string

    if (isSpace(c)) {
      let j = i
      while (j < n && isSpace(src[j] as string)) j++
      out.push({ kind: 'space', text: src.slice(i, j) })
      i = j
      continue
    }

    // Line comment, or an AXTAG. `;@axiom:` is recognised only in a line
    // comment (docs/reference.md, "Comments").
    if (c === ';') {
      let j = i
      while (j < n && src[j] !== '\n') j++
      const text = src.slice(i, j)
      out.push({ kind: text.startsWith(';@axiom:') ? 'axtag' : 'comment', text })
      i = j
      continue
    }

    // Nesting block comment `#| ... |#`: the first `|#` closes only the
    // innermost, and an unclosed one runs to end of file.
    if (c === '#' && src[i + 1] === '|') {
      let depth = 1
      let j = i + 2
      while (j < n && depth > 0) {
        if (src[j] === '#' && src[j + 1] === '|') { depth++; j += 2 }
        else if (src[j] === '|' && src[j + 1] === '#') { depth--; j += 2 }
        else j++
      }
      out.push({ kind: 'comment', text: src.slice(i, j) })
      i = j
      continue
    }

    if (c === '"') {
      let j = i + 1
      while (j < n) {
        if (src[j] === '\\') { j += 2; continue }
        if (src[j] === '"') { j++; break }
        j++
      }
      out.push({ kind: 'string', text: src.slice(i, j) })
      i = j
      continue
    }

    // Character literal: quote, one character (a bare quote included) or
    // an escape, then quote.
    if (c === "'") {
      let len = 0
      if (src[i + 1] === '\\' && src[i + 3] === "'") len = 4
      else if (src[i + 2] === "'") len = 3
      if (len > 0) {
        out.push({ kind: 'char', text: src.slice(i, i + len) })
        i += len
        continue
      }
    }

    if (isBracket(c)) {
      out.push({
        kind: c === '(' || c === '[' || c === '{' ? 'open' : 'close',
        text: c,
      })
      i++
      continue
    }

    let j = i
    while (
      j < n &&
      !isSpace(src[j] as string) &&
      !isBracket(src[j] as string) &&
      src[j] !== ';' &&
      src[j] !== '"'
    ) j++
    if (j === i) j = i + 1
    out.push({ kind: 'atom', text: src.slice(i, j) })
    i = j
  }

  return out
}

/**
 * One open bracket's worth of context. A token's role is decided by
 * where it sits in the form around it, which is exactly what the
 * `field(...)` labels in the grammar encode.
 */
interface Frame {
  /** The form's head atom, once seen (`fn`, `::`, `data`, `match`, …). */
  head: string | null
  /** Items seen so far in this form, trivia excluded. */
  index: number
  /**
   * Which index the head sits at. `pub` is a visibility marker rather
   * than a head, so `(pub fn (f) …)` heads at 1, not 0.
   */
  headIndex: number
  /** Everything inside is a type: a `::` tail, an arrow, `[T]`. */
  typeCtx: boolean
  /** Everything inside is a pattern: a `match` arm's left-hand side. */
  patternCtx: boolean
  /** The bracket that opened it. */
  open: string
  /** `(fn (name a b) …)`: this frame is the header list. */
  header: boolean
  /** `(a e)` after `data`/`struct`: a type-parameter list. */
  tyvars: boolean
  /** What this form declares, for the frames nested inside it. */
  declKind: 'data' | 'struct' | 'match' | 'let' | 'effect' | 'arm' | null
}

function newFrame(open: string): Frame {
  return {
    head: null,
    index: 0,
    headIndex: 0,
    typeCtx: false,
    patternCtx: false,
    open,
    header: false,
    tyvars: false,
    declKind: null,
  }
}

const isUpper = (t: string) => /^[A-Z]/.test(t)

function classifyAtom(text: string, frame: Frame, parent: Frame | undefined): Capture {
  const arg = frame.index - frame.headIndex
  const head = arg === 0
  const upper = isUpper(text)

  // --- shapes that win everywhere -------------------------------------
  if (text === '_') return 'character.special'
  if (text === 'true' || text === 'false') return 'boolean'
  if (/^-?[0-9][0-9_]*\.[0-9][0-9_]*([eE][+-]?[0-9]+)?$/.test(text)) return 'number'
  if (/^-?[0-9][0-9_]*$/.test(text)) return 'number'
  if (DELIMITERS.has(text)) return 'punctuation.delimiter'
  if (text === 'pub' && frame.index === 0) return 'keyword'
  if (text === 'mut') return 'keyword.modifier'

  // A removed construct in head position is what the compiler answers
  // AX2004 for, and highlights.scm paints it as an error.
  if (head && REMOVED.has(text)) return 'error'

  // --- type-parameter list, `(data Maybe (a) …)` -----------------------
  if (frame.tyvars) return 'variable.parameter'

  // --- declaration names, by role -------------------------------------
  if (arg === 1) {
    switch (frame.head) {
      case '::':
        return 'function'
      case 'import':
        return 'module'
      case 'data':
      case 'struct':
        return 'type'
      case 'type':
        return 'type.definition'
      case 'effect':
        return 'keyword.modifier'
      default:
        break
    }
  }

  // `(fn (name p q) …)` — the header list: head is the function's name,
  // the rest are its parameters.
  if (frame.header) return head ? 'function' : 'variable.parameter'

  if (parent) {
    const parentArg = parent.index - parent.headIndex
    // A `(Ctor Field …)` inside `data`, or `(name Type)` inside `struct`.
    if (parent.declKind === 'data' && parentArg >= 2 && head && upper) {
      return 'constructor'
    }
    if (parent.declKind === 'struct' && parentArg >= 2 && head && !upper) {
      return 'variable.member'
    }
    // An operation inside `(effect E (op :: (-> …)))`.
    if (parent.declKind === 'effect' && parentArg >= 2 && head) {
      return 'function.method'
    }
    // A binder in a `let` binding list.
    if (parent.declKind === 'let' && head && !upper) return 'variable'
  }

  // --- type position ---------------------------------------------------
  if (frame.typeCtx) {
    if (BUILTIN_TYPES.has(text)) return 'type.builtin'
    if (BUILTIN_EFFECTS.has(text)) return 'keyword.modifier'
    if (upper) return 'type'
    // A lowercase name in type position is a type variable.
    return 'variable.parameter'
  }

  if (BUILTIN_TYPES.has(text)) return 'type.builtin'

  // --- pattern position ------------------------------------------------
  if (frame.patternCtx) return upper || head ? 'constructor' : 'variable'

  // --- keywords, in head position only ---------------------------------
  if (head) {
    if (KEYWORD_FUNCTION.has(text)) return 'keyword.function'
    if (KEYWORD_TYPE.has(text)) return 'keyword.type'
    if (KEYWORD_CONDITIONAL.has(text)) return 'keyword.conditional'
    if (KEYWORD_PLAIN.has(text)) return 'keyword'
    if (KEYWORD_MODIFIER.has(text)) return 'keyword.modifier'
    if (upper) return 'constructor'
    // Axiom has no operator syntax, so `(f x)` and `(+ 1 2)` are the same
    // shape: the head of an application is the thing being called.
    return 'function.call'
  }

  if (upper) return 'constructor'
  return 'variable'
}

/** Split a string literal so interpolation holes read as holes. */
function splitString(text: string): Token[] {
  const out: Token[] = []
  const re = /\{[A-Za-z_][A-Za-z0-9_'.]*(?::[^}]*)?\}/g
  let last = 0
  let m: RegExpExecArray | null
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push({ text: text.slice(last, m.index), capture: 'string' })
    out.push({ text: m[0], capture: 'string.hole' })
    last = m.index + m[0].length
  }
  if (last < text.length) out.push({ text: text.slice(last), capture: 'string' })
  return out
}

export function highlight(source: string): Token[] {
  const raws = scan(source)
  const tokens: Token[] = []
  const stack: Frame[] = [newFrame('')]

  for (const raw of raws) {
    const frame = stack[stack.length - 1] as Frame
    const parent = stack[stack.length - 2]
    const arg = frame.index - frame.headIndex

    switch (raw.kind) {
      case 'space':
        tokens.push({ text: raw.text, capture: 'text' })
        continue

      case 'comment':
        tokens.push({ text: raw.text, capture: 'comment' })
        continue

      case 'axtag':
        tokens.push({ text: raw.text, capture: 'attribute' })
        continue

      case 'string':
        tokens.push(...splitString(raw.text))
        frame.index++
        continue

      case 'char':
        tokens.push({ text: raw.text, capture: 'character' })
        frame.index++
        continue

      case 'open': {
        tokens.push({ text: raw.text, capture: 'punctuation.bracket' })
        const child = newFrame(raw.text)

        // `[T]` is a list type; a `::` signature's tail is all type; an
        // arrow's arguments are types.
        child.typeCtx =
          raw.text === '[' ||
          frame.typeCtx ||
          (frame.head === '::' && arg >= 2) ||
          (frame.head === '->' && arg >= 1)

        // `(fn (name a b) …)` / `(define (name a) …)` header list.
        child.header =
          (frame.head === 'fn' ||
            frame.head === 'define' ||
            frame.head === 'lambda') &&
          arg === 1 &&
          raw.text === '('

        // A `match` arm is `(pattern body)`: only the arm's first child
        // is a pattern.
        if (frame.declKind === 'match' && arg >= 2) child.declKind = 'arm'
        if (frame.declKind === 'arm' && frame.index === 0) child.patternCtx = true

        // `(let ((x 1) (y 2)) …)`: the binding list, then each binder.
        if (frame.head === 'let' && arg === 1) child.declKind = 'let'

        frame.index++
        stack.push(child)
        continue
      }

      case 'close':
        tokens.push({ text: raw.text, capture: 'punctuation.bracket' })
        if (stack.length > 1) stack.pop()
        continue

      case 'atom': {
        // `pub` is a visibility marker, not the head: the head is the
        // token after it.
        if (frame.index === 0 && raw.text === 'pub') {
          tokens.push({ text: raw.text, capture: 'keyword' })
          frame.headIndex = 1
          frame.index = 1
          continue
        }

        if (arg === 0) {
          frame.head = raw.text
          switch (raw.text) {
            case 'data': frame.declKind = 'data'; break
            case 'struct': frame.declKind = 'struct'; break
            case 'match': frame.declKind = 'match'; break
            case 'let': frame.declKind = 'let'; break
            case 'effect': frame.declKind = 'effect'; break
            default: break
          }

          // Inside a `data` body: an uppercase head opens a constructor
          // form, whose remaining atoms are field TYPES; a lowercase head
          // opens the type-parameter list. Inside a `struct` body an
          // uppercase head is the same, a lowercase one is a field whose
          // tail after `:` is a type.
          if (parent) {
            const parentArg = parent.index - parent.headIndex
            const inData = parent.declKind === 'data' && parentArg >= 2
            const inStruct = parent.declKind === 'struct' && parentArg >= 2
            if ((inData || inStruct) && !isUpper(raw.text)) {
              if (inData) frame.tyvars = true
            }
            if ((inData || inStruct) && isUpper(raw.text)) {
              // constructor form: everything after the name is a type
              frame.typeCtx = false
            }
          }
        }

        const capture = classifyAtom(raw.text, frame, parent)
        tokens.push({ text: raw.text, capture })

        // After the head of a constructor form or the `:` of a field
        // form, the rest of the form is type position.
        if (parent) {
          const parentArg = parent.index - parent.headIndex
          const inData = parent.declKind === 'data' && parentArg >= 2
          const inStruct = parent.declKind === 'struct' && parentArg >= 2
          const inEffect = parent.declKind === 'effect' && parentArg >= 2
          if (inData && arg === 0 && isUpper(raw.text)) frame.typeCtx = true
          if ((inStruct || inEffect) && raw.text === ':') frame.typeCtx = true
          if (inEffect && raw.text === '::') frame.typeCtx = true
        }
        if (frame.head === '->' && arg === 0) frame.typeCtx = true

        frame.index++
        continue
      }
    }
  }

  return tokens
}
