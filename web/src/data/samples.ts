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

// SIX RECIPES, AND EVERY ONE OF THEM RAN.
//
// The set these replaced were feature demos in costume: a function that
// parsed the literal string "8080", a handler that logged
// "starting"/"done". A reader could tell they were written to show a
// language feature rather than to do a job, which is the fastest way to
// lose one.
//
// Each of these is a small real task. Each was written against the
// standard library as it actually is, compiled, run, and formatted by
// `axiom fmt`, so what is shown IS the formatter's normal form. The
// `result` field is the observed stdout, not a guess.
//
// The ORDER is an argument, not a menu: types, then failure, then
// effects, then data, then memory, then concurrency. It walks a reader
// from the thing every language has to the thing only this one does.
export const SAMPLES: Sample[] = [
  {
    id: 'types',
    tab: 'parcels.ax',
    title: "Shipment status report",
    note: "Add a fifth state and the compiler names both places it belongs.",
    result: "parcel   status                action\nAX-1041  packing               not shipped yet\nAX-1042  DHL, 2 days out       -\nAX-1043  held at customs       call about customs\nAX-1044  delivered             -",
    docs: { label: "Pattern Matching", href: `${REF}#pattern-matching` },
    code: `(import IO)

(import Err)

(data Parcel
  (Ordered)
  (InTransit { carrier : String, days : Int })
  (Held { why : String })
  (Delivered))

(:: status (-> Parcel String))

(fn (status p)
  (match p
    ((Ordered) "packing")
    ((InTransit carrier days) (format "{carrier}, {days} days out"))
    ((Held why) (format "held at {why}"))
    ((Delivered) "delivered")
  )
)

(:: alert (-> Parcel (Option String)))

(fn (alert p)
  (match p
    ((Ordered) (Some "not shipped yet"))
    ((InTransit _ _) None)
    ((Held why) (Some (format "call about {why}")))
    ((Delivered) None)
  )
)

(:: row (-> String Parcel Int))

;@axiom:effect(io)
(fn (row id p)
  (let (
    (s (status p))
    (a (optUnwrapOr (alert p) "-"))
  )
    (println "{id:<9}{s:<22}{a}")
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println "parcel   status                action")
    (row "AX-1041" Ordered)
    (row "AX-1042" (InTransit "DHL" 2))
    (row "AX-1043" (Held "customs"))
    (row "AX-1044" Delivered)
    0
  }
)`,
  },
  {
    id: 'failure',
    tab: 'settings.ax',
    title: "Three steps, one error path",
    note: "Three fallible steps, one arm to handle them, and the error still says which step failed.",
    result: "4096 x 256 = 1048576 bytes\n4 KiB is not a number while reading chunk\nproduct is not representable while sizing the upload",
    docs: { label: "The error model", href: `${LIB}docs/error-model.md` },
    code: `(import Err)

(import IO)

(import Str)

(:: number (-> String String (Result Int Error)))

(fn (number name text)
  (let ((bad (mkError 20 (strConcat text " is not a number"))))
    (withContext (okOr (strParseInt text) bad) (strConcat "reading " name))
  )
)

; \`*\` wraps silently on overflow; this is the one that can say no.
(:: upload (-> Int Int (Result Int Error)))

(fn (upload chunk parts) (withContext (mulChecked chunk parts) "sizing the upload"))

(:: report (-> String String Int))

;@axiom:effect(io)
(fn (report chunk parts)
  (match (try! size (number "chunk" chunk) (try! n (number "parts" parts) (upload size n)))
    ((Ok total) (println "{chunk} x {parts} = {total} bytes"))
    ((Err e) (eprintln (errorText e)))
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (report "4096" "256")
    (report "4 KiB" "256")
    (report "4096" "9007199254740993")
    0
  }
)`,
  },
  {
    id: 'effects',
    tab: 'audit.ax',
    title: "Capturing the log for tests",
    note: "The same function prints in production and hands the test its output as data. One `handle` apart, no mocking framework.",
    result: "skipped: n/a\n42\nok\n",
    docs: { label: "Effects", href: `${REF}#effects` },
    code: `(import IO)

(import Str)

(import Test)

(import Vec)

(effect Log
  (log :: (-> String Int)))

(:: total (-> (Vec String) Int))

;@axiom:effect(log)
(fn (total rows)
  (let ((mut sum 0))
    {
      (for row rows
        (match (strParseInt (strTrim row))
          ((Some n)
            (set sum (+ sum n))
          )
          ((None) (log (strConcat "skipped: " row)))
        ))
      sum
    }
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (rows vecNew)
    (seen vecNew)
  )
    {
      (vecPush rows "12")
      (vecPush rows " 30 ")
      (vecPush rows "n/a")
      (println
        (handle (total rows) (Log Alloc Mut) (lambda (m) (println m)))
      )
      (let ((sum 
        (handle (total rows) (Log Alloc Mut) (lambda (m) (vecLen (vecPush seen m))))
      ))
        {
          (assertEq "same total, nothing printed" 42 sum)
          (assertStrEq "the warning was captured" "skipped: n/a" (vecGet seen 0))
        }
      )
      (println "ok")
      0
    }
  )
)`,
  },
  {
    id: 'data',
    tab: 'inbox.ax',
    title: "Top words in a support inbox",
    note: "Count into a `Map`, take its keys, sort them by what they point at.",
    result: "   4  mobile\n   3  checkout\n   3  payment\n   3  safari\n   2  error\n",
    docs: { label: "Standard Library", href: `${REF}#standard-library` },
    code: `; Split on 32 (' ') for pieces, then each piece on 46 ('.'), so "Safari." counts as safari.
(import IO)

(import Str)

(import Vec)

(import Map)

(import Intern)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (pieces (strSplit (strLower "Checkout fails on mobile Safari. The payment sheet spins forever and never loads. Checkout works on desktop but the payment button is greyed out on mobile. Payment declined with no error message on mobile Safari. Safari on iOS shows the same error. Checkout on mobile is unusable.") 32))
    (seen internNew)
    (count mapNew)
    (byCount (lambda (a b) (- (mapGet count b 0) (mapGet count a 0))))
  )
    {
      (for i 0 (vecLen pieces)
        (let ((w (vecGetStr (strSplit (vecGetStr pieces i) 46) 0)))
          (if (>= (strLen w) 4)
            (let ((id (internIntern seen w)))
              (mapInsert count id (+ 1 (mapGet count id 0)))
            )
            0
          )
        ))
      (let ((ranked (vecSortBy (mapKeys count) byCount)))
        (for r 0 5
          (let (
            (n (mapGet count (vecGet ranked r) 0))
            (w (internLookup seen (vecGet ranked r)))
          )
            (println "{n:>4}  {w}")
          ))
      )
      0
    }
  )
)`,
  },
  {
    id: 'memory',
    tab: 'ledger.ax',
    title: "A region per row",
    note: "Five rows and a hundred thousand rows cost the same memory. The program prints the arena to prove it.",
    result: "5 rows, 10374 cents, arena +48 bytes",
    docs: { label: "Memory Primitives", href: `${REF}#memory-primitives` },
    code: `(import IO)

(import Str)

(import Vec)

(import Err)

(import Mem)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (rows (strSplit "coffee,450\\nbooks,2299\\nfuel,5410\\nlunch,1875\\nstamps,340" 10))
    (n (vecLen rows))
    (mut cents 0)
    (mark __axiom_arena_mark)
  )
    {
      (for i 0 n
        (region r
          (let ((cols (strSplit (vecGetStr rows i) 44)))
            (set cents (+ cents (optUnwrapOr (strParseInt (vecGetStr cols 1)) 0)))
          )))
      (let ((held (- (memGetWord __axiom_arena_mark 0) (memGetWord mark 0))))
        (println "{n} rows, {cents} cents, arena +{held} bytes")
      )
      0
    }
  )
)`,
  },
  {
    id: 'concurrency',
    tab: 'triage.ax',
    title: "Sharded log triage",
    note: "Three shards scanned beside each other, joined in the order written.",
    result: "errors  us 1  eu 2  apac 0  total 3",
    docs: { label: "parallel", href: `${REF}#parallel--bindings-that-run-beside-the-caller` },
    code: `(import IO)

(import Str)

(:: errors (-> String Int Int))

(fn (errors shard from)
  (match (strFind shard "ERROR" from)
    ((None) 0)
    ((Some at) (+ 1 (errors shard (+ at 1))))
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  ; A join carries one machine word, so a shard answers its count.
  (parallel scan (
    (us (errors "INFO up\\nERROR db timeout\\nWARN slow disk\\n" 0))
    (eu (errors "ERROR db timeout\\nERROR cache miss\\nINFO up\\n" 0))
    (apac (errors "INFO up\\nWARN slow disk\\nINFO up\\n" 0))
  )
    (let ((total (+ us (+ eu apac))))
      {
        (println "errors  us {us}  eu {eu}  apac {apac}  total {total}")
        0
      }
    )
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
