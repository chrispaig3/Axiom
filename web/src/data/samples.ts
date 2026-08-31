/**
 * Every program on this site was compiled and run against a compiler
 * built from this tree before it was published, and the `result` field
 * is its real output:
 *
 *   ./scripts/build-shared-axc.sh /tmp/axc/axc
 *   AXIOM_STDLIB=./stdlib /tmp/axc/axc run <file>.ax
 *
 * Nothing here is written from memory of what Axiom looks like, and
 * nothing is a fragment that would not compile on its own.
 */

export interface Sample {
  id: string
  /** Label on the tab strip. */
  tab: string
  title: string
  /** One sentence on what it demonstrates. Backticks become <code>. */
  note: string
  code: string
  /** The program's real output, for samples that are whole programs. */
  result?: string
  /** For excerpts: the repo path it was copied from, and its link. */
  source?: string
  href?: string
  /** Optional: the doc section this idiom is specified in. */
  docs?: { label: string; href: string }
}

const LIB = 'https://github.com/chrispaig3/Axiom/blob/trunk/'
const REF = `${LIB}docs/reference.md`

/** The hero program. */
export const HERO: Sample = {
  id: 'shapes',
  tab: 'shapes.ax',
  title: 'A whole program',
  note: '',
  result: 'circle = 48\nsquare = 36',
  code: `(import IO)

(data Shape
  (Circle Int)
  (Square Int))

(:: area (-> Shape Int))

(fn (area s)
  (match s
    ((Circle r) (* 3 (* r r)))
    ((Square w) (* w w))
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (c (area (Circle 4)))
    (q (area (Square 6)))
  )
    {
      (println "circle = {c}")
      (println "square = {q}")
      0
    }
  )
)`,
}

export const SAMPLES: Sample[] = [
  {
    id: 'result',
    tab: 'parse.ax',
    title: 'Failure is a value',
    note: 'No exceptions and no null. `Option` and `Result` are ordinary data types from the standard library, and `match` on them has to be total.',
    result: 'listening on :8080',
    docs: { label: 'Pattern matching', href: `${REF}#pattern-matching` },
    code: `(import IO)

(import Str)

(import Err)

(:: parsePort (-> String (Result Int Error)))

(fn (parsePort s)
  (match (strParseInt s)
    ((Some n)
      (if (&& (> n 0) (< n 65536))
        (Ok n)
        (Err (mkError 2 "port out of range"))
      )
    )
    ((None) (Err (mkError 1 "not a number")))
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (match (parsePort "8080")
    ((Ok p) { (println "listening on :{p}") 0 })
    ((Err e)
      (let ((why (errMessage e)))
        { (eprintln "bad port: {why}") 1 }))
  )
)`,
  },
  {
    id: 'effects',
    tab: 'handler.ax',
    title: 'The caller chooses the interpretation',
    note: '`work` never names a handler and still reaches the one installed around its caller. Same function, two meanings: the first `handle` prints, the second swallows.',
    result: '[log] starting\n[log] done',
    docs: { label: 'Effects', href: `${REF}#effects` },
    code: `(import IO)

(effect Log
  (write :: (-> String Int)))

(:: work (-> Int Int))

(fn (work n)
  {
    (write "starting")
    (write "done")
    n
  }
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (handle (work 1) (Log IO) (lambda (m) { (println "[log] {m}") 0 }))
    (handle (work 2) (Log) (lambda (m) 0))
    0
  }
)`,
  },
  {
    id: 'capability',
    tab: 'sink.ax',
    title: 'An interface is a value',
    note: 'This is what replaced traits in 0.6.0: a parameterised struct whose fields are functions. The record is an ordinary value, so it can be built at run time, passed as an argument, or stored in a `Vec`.',
    result: 'the record is an ordinary value\nso the instance can be chosen at run time',
    docs: { label: 'Capability records', href: `${REF}#capability-records` },
    code: `(import IO)

(struct Sink (a)
  (emit : (-> a Int)))

;@axiom:effect(io)
(:: toStdout (-> String Int))

;@axiom:effect(io)
(fn (toStdout s) (println s))

;@axiom:effect(io)
(:: toStderr (-> String Int))

;@axiom:effect(io)
(fn (toStderr s) (eprintln s))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (out (Sink toStdout))
    (log (Sink toStderr))
  )
    {
      (out.emit "the record is an ordinary value")
      (log.emit "so the instance can be chosen at run time")
      0
    }
  )
)`,
  },
  {
    id: 'macros',
    tab: 'Pre.ax',
    title: 'Control flow you can add yourself',
    note: 'Code is data, so a macro is a pattern over the tree. These two ship in the prelude, and both expand before the type checker runs — so everything a macro generates is checked like anything else.',
    source: 'stdlib/Pre.ax',
    href: `${LIB}stdlib/Pre.ax`,
    code: `;; when \u2014 conditionally evaluate body
;; (when test body) -> (if test body 0)
(pub macro (when test body) (if test
  body
  0
))

;; unless \u2014 evaluate body unless test is true
;; (unless test body) -> (if test 0 body)
(pub macro (unless test body) (if test
  0
  body
))`,
  },
  {
    id: 'lexer',
    tab: 'lexer.ax',
    title: "The compiler's own source",
    note: "Skipping whitespace, from the lexer that reads every Axiom program. The `restrict` line is a claim the compiler checks against the call graph, and the comment records why the loop is a loop \u2014 a measurement, kept where the next reader will need it.",
    source: 'self_host/lexer.ax',
    href: `${LIB}self_host/lexer.ax#L155-L187`,
    code: `;@axiom:restrict(no-io,no-alloc,no-foreign)
(pub :: skipWhitespace (-> String Int Int Int))

; A loop rather than a recursion, and \`skipLineComment\` returns to it
; rather than calling back, for the reason \`lexTokens\` below is a loop:
; the two used to call each other in tail position, one frame per byte
; of a comment-and-whitespace run, and stage1's tail-call rewrite fires
; only for a SELF call.
(pub fn (skipWhitespace src pos len)
  (let (
    (mut p pos)
    (mut go 1)
  )
    {
      (while (== go 1)
        (if (>= p len)
          (set go 0)
          (let ((ch (strByte src p)))
            (if (isSpace ch)
              (set p (+ p 1))
              (if (== ch 59)
                (set p (skipLineComment src (+ p 1) len))
                (if (&& (== ch 35) (isBlockOpen src p len))
                  (set p (skipBlockComment src (+ p 2) len))
                  (set go 0)
                )
              )
            )
          )
        ))
      p
    }
  )
)`,
  },
]

/* ------------------------------------------------------------------ *
 * The agent-facing notation. Every block below is quoted exactly, from
 * the file named beside it.
 * ------------------------------------------------------------------ */

/**
 * README.md, "Error Messages" — a doc-gated block. The whole showcase is
 * re-rendered against the live compiler by scripts/check-doc-drift.sh on
 * every run, so what is quoted here cannot drift from what the compiler
 * actually prints.
 */
export const SET_SOURCE = `(:: main Int)
(fn (main)
  (let ((x 0))
    {
      (set x 1)
      x
    }))`

/** README.md — the human render: two spans, an elision, and two helps. */
export const SET_HUMAN = `error[AX3012]: cannot assign to immutable binding \`x\`
 --> count.ax:5:12
  |
3 |   (let ((x 0))
  |          - \`x\` is bound here
...
5 |       (set x 1)
  |            ^ \`x\` cannot be assigned
  |
  = help: declare it mutable: \`(mut x ...)\` ~> mut x
  = help: only a binding introduced by \`(let ((mut x ...)) ...)\` may be the target of \`set\`
  = help: run \`axiom explain AX3012\` for a full explanation

compilation failed due to 1 previous error`

/** README.md — the same diagnostic on one line. */
export const SET_AXDL =
  'E AX3012 count.ax:5:12-13 assign-to-immutable "cannot assign to immutable binding `x`" #"`x` cannot be assigned" ^3:10-11:"`x` is bound here" ?3:10-11:"declare it mutable: `(mut x ...)`"~>"mut x" ?"only a binding introduced by `(let ((mut x ...)) ...)` may be the target of `set`"'

/** docs/diagnostics.md — a typo on line 6, and the fix that travels with it. */
export const FIX_SOURCE = `(:: helper (-> Int Int))
(define (helper x) (+ x 1))

(:: main Int)
(define main
  (helpr 5))`

/** docs/diagnostics.md. Exactly 193 bytes. */
export const FIX_AXDL =
  'E AX3001 main.ax:6:4-9 undefined-variable "undefined variable `helpr`" #"no binding named `helpr` in scope" ?6:4-9:"a similarly named binding `helper` is in scope; did you mean this?"~>"helper"'

/** docs/diagnostics.md — the same diagnostic as JSON Lines. */
export const FIX_JSON =
  '{"severity":"error","code":"AX3001","slug":"undefined-variable","message":"undefined variable `helpr`","file":"main.ax","span":{"start":{"line":6,"col":4},"end":{"line":6,"col":9},"char_start":84,"char_end":89},"label":"no binding named `helpr` in scope","related":[],"notes":[],"help":["a similarly named binding `helper` is in scope; did you mean this?"],"expansion":[]}'

/** docs/diagnostics.md — the file AXSYM is demonstrated on. */
export const AXSYM_SOURCE = `(data Maybe (a)
  (Nothing)
  (Just a))

(struct Point
  (x : Int)
  (y : Int))

(:: add (-> Int Int Int))
(fn (add x y)
  (+ x y))`

/** docs/diagnostics.md — the default, aligned table. */
export const AXSYM_TABLE = `Fn       add                  (Int -> (Int -> Int))                    [main.ax:9:5-8]
Data     Option               data Option                              [builtin]
Ctor     Some                 (a -> Option a)                          [builtin]
Ctor     None                 Option a                                 [builtin]
Data     Maybe                data Maybe                               [main.ax:1:7-12]
Ctor     Nothing              Maybe a                                  [main.ax:2:4-11]
Ctor     Just                 (a -> Maybe a)                           [main.ax:3:4-8]
Struct   Point                struct Point                             [main.ax:5:9-14]`

/** docs/diagnostics.md — the same file under --diagnostic-format=ai. */
export const AXSYM_AI = `F add main.ax:9:5-8 "(Int -> (Int -> Int))" @27bcb2cac184465e
D Option - "data Option" #ctors=Some,None
C Some - "(a -> Option a)" #of=Option
C None - "Option a" #of=Option
D Maybe main.ax:1:7-12 "data Maybe" @247d1682b2330461 #ctors=Nothing,Just
C Nothing main.ax:2:4-11 "Maybe a" #of=Maybe
C Just main.ax:3:4-8 "(a -> Maybe a)" #of=Maybe
S Point main.ax:5:9-14 "struct Point" @aa47cd1e9254cc56 #fields=x:Int,y:Int`
