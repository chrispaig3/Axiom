/**
 * Every program on this site, and every piece of compiler output shown
 * beside one, is real: compiled, run and captured from a compiler built
 * from this tree.
 *
 * AND IT IS RE-CHECKED, not remembered. `scripts/check-samples.mjs`
 * writes each program to a scratch directory and requires that
 *
 *   - `axiom fmt --check` accepts it, so what is shown IS the
 *     formatter's normal form;
 *   - `axiom run` (or `axiom test`) prints exactly `output`;
 *   - each refused program fails `axiom check` with exactly the report
 *     quoted beside it;
 *   - every point pinned to a line names text that is on exactly one
 *     line, so a highlight cannot drift from the sentence it belongs to;
 *   - the landing demo, replayed edit by edit, prints what every one of
 *     its commands shows;
 *   - the Rust excerpt is a verbatim slice of the crate it names.
 *
 *   ./scripts/bootstrap-from-seed.sh --install .axiom-bin
 *   cd web && npm run check:samples
 *
 * Run it after changing a sample, the compiler, or the standard
 * library. A sample that drifts fails there, not on the page.
 */

export interface Refusal {
  /** Button label: the change a reader is invited to make. */
  label: string
  /** One or two sentences on what the compiler does about it. */
  note: string
  /** The whole changed program. */
  code: string
  /** `axiom check` on it: stderr, the human renderer, colour removed. */
  human: string
}

/**
 * One thing to notice, pinned to a line. `at` is text that appears on
 * exactly one line of the program; hovering the point marks that line.
 * The line is found, never numbered by hand, and the checker fails a
 * point whose text is on no line or on two.
 */
export interface Point {
  at: string
  text: string
}

export interface Program {
  id: string
  /** The file name it runs as, and the label on its frame. */
  file: string
  /** Short label for a tab or a chapter list. */
  tab: string
  title: string
  /** What it shows, in a sentence or two. Backticks become <code>. */
  lede: string
  points: Point[]
  code: string
  /** Its real stdout. */
  output: string
  /** `run` unless stated. */
  mode?: 'run' | 'test'
  /** A crate directory, relative to the repository, passed as `--crate`. */
  crate?: string
  /** For a program that calls Rust: the crate side, quoted verbatim. */
  rust?: { path: string; code: string }
  refusal?: Refusal
  docs?: { label: string; href: string }
}

const LIB = 'https://github.com/chrispaig3/Axiom/blob/trunk/'
const REF = `${LIB}docs/reference.md`

/** The shell command that produced a program's output. */
export function commandFor(p: Program): string {
  const verb = p.mode ?? 'run'
  return `axiom ${verb} ${p.file}${p.crate ? ` --crate ${p.crate}` : ''}`
}

/**
 * The program the landing demo types first: a sum type with named
 * fields, an exhaustive match, a function that promises no I/O, and one
 * that declares it does. Checked on its own as well as in the demo.
 */
export const HERO: Program = {
  id: 'shapes',
  file: 'shapes.ax',
  tab: 'shapes.ax',
  title: 'A whole program',
  lede: '',
  points: [],
  output: `circle       12.57
rect         13.50
triangle      6.00`,
  code: `(import IO)

(data Shape
  (Circle { r : Float })
  (Rect { w : Float, h : Float })
  (Triangle { b : Float, h : Float }))

(:: area (-> Shape Float))
;@axiom:restrict(no-io)
(fn (area s)
  (match s
    ((Circle {r = r}) (* 3.14159 (* r r)))
    ((Rect {w = w, h = h}) (* w h))
    ((Triangle {b = b, h = h}) (/ (* b h) 2.0))))

(:: report (-> String Shape Int))
;@axiom:effect(io)
(fn (report name s)
  (let ((a (area s)))
    (println "{name:<10}{a:>8.2}")))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (report "circle" (Circle 2.0))
    (report "rect" (Rect 3.0 4.5))
    (report "triangle" (Triangle 4.0 3.0))
    0
  })`,
}

/**
 * The landing demo: a script, not a recording.
 *
 * The page plays it as a terminal session - `shapes.ax` typed into an
 * editor pane, then run, broken, refused, fixed and built in a shell
 * pane - and `check-samples.mjs` replays the same steps against the
 * compiler: it applies every edit, and at every `run` writes the
 * buffer out, requires it to be in `axiom fmt` normal form, runs the
 * command and compares what it prints, byte for byte. So the video
 * cannot show a program or an answer the compiler does not give.
 *
 * Highlights are not written here at all. An edit marks the lines it
 * touched, and a refusal marks the line its `-->` names, so what is lit
 * is always what the caption is about.
 */
export type DemoStep =
  | { do: 'chapter'; name: string }
  /** The caption from here on. Backticks become <code>. */
  | { do: 'say'; text: string }
  /** Type at the editor's cursor. */
  | { do: 'type'; text: string }
  /** Put the editor's cursor just after the first occurrence of `text`. */
  | { do: 'after'; text: string }
  /**
   * Type `command` at the shell prompt and run it. `argv` is what the
   * checker runs, one process per entry (`./x` runs what a step built),
   * and `output` is what it printed: stdout, or on `exit: 1` the human
   * report on stderr with its colour removed.
   */
  | { do: 'run'; command: string; argv: string[][]; output: string; exit?: 1 }
  | { do: 'wait'; ms: number }

/** The file the demo edits, runs and builds. */
export const DEMO_FILE = 'shapes.ax'

/** HERO's text, cut before each marker: the demo types it in three parts. */
function cut(code: string, ...marks: string[]): string[] {
  const parts: string[] = []
  let rest = code
  for (const m of marks) {
    const i = rest.indexOf(m)
    if (i < 0) throw new Error(`samples.ts: HERO has no ${JSON.stringify(m)}`)
    parts.push(rest.slice(0, i))
    rest = rest.slice(i)
  }
  return [...parts, rest]
}

const [TYPES, AREA, REST] = cut(HERO.code, '(:: area', '(:: report') as [string, string, string]

const RAN = `circle       12.57
rect         13.50
triangle      6.00`

const RAN_4 = `${RAN}
hexagon      10.39`

export const DEMO: DemoStep[] = [
  { do: 'chapter', name: 'write' },
  { do: 'say', text: 'A sum type: three shapes, each with named fields.' },
  { do: 'type', text: TYPES },
  { do: 'say', text: '`area` promises it performs no I/O. The compiler holds it to that.' },
  { do: 'type', text: AREA },
  { do: 'say', text: '`report` prints, so it says so: `effect(io)`.' },
  { do: 'type', text: REST },

  { do: 'chapter', name: 'run' },
  { do: 'say', text: 'Compile and run in one step. No build file.' },
  { do: 'run', command: `axiom run ${DEMO_FILE}`, argv: [['run', DEMO_FILE]], output: RAN },
  { do: 'wait', ms: 1400 },

  { do: 'chapter', name: 'break' },
  { do: 'say', text: 'Add a fourth shape, and nothing else.' },
  { do: 'after', text: '(Triangle { b : Float, h : Float })' },
  { do: 'type', text: '\n  (Hexagon { side : Float })' },
  { do: 'say', text: 'The `match` in `area` no longer covers every shape. The compiler names it, and the missing arm.' },
  {
    do: 'run',
    command: `axiom check ${DEMO_FILE}`,
    argv: [['check', DEMO_FILE]],
    exit: 1,
    output: `error[AX3005]: non-exhaustive pattern match: missing Hexagon
  --> shapes.ax:12:10
   |
12 |   (match s
   |          ^ this \`match\` does not cover: Hexagon
   |
   = help: add the missing arms, each a \`todo\` until it is written ~>
               ((Hexagon _) (todo "Hexagon"))
   = help: run \`axiom explain AX3005\` for a full explanation

compilation failed due to 1 previous error`,
  },
  { do: 'wait', ms: 3600 },

  { do: 'chapter', name: 'fix' },
  { do: 'say', text: 'Handle the hexagon, and report one.' },
  { do: 'after', text: '((Triangle {b = b, h = h}) (/ (* b h) 2.0))' },
  { do: 'type', text: '\n    ((Hexagon {side = a}) (* 2.598076 (* a a)))' },
  { do: 'after', text: '(report "triangle" (Triangle 4.0 3.0))' },
  { do: 'type', text: '\n    (report "hexagon" (Hexagon 2.0))' },
  { do: 'run', command: `axiom run ${DEMO_FILE}`, argv: [['run', DEMO_FILE]], output: RAN_4 },
  { do: 'wait', ms: 1400 },

  { do: 'chapter', name: 'ship' },
  { do: 'say', text: 'A native executable, with its allocator and syscalls inside it.' },
  {
    do: 'run',
    command: `axiom build ${DEMO_FILE} -o shapes`,
    argv: [['build', DEMO_FILE, '-o', 'shapes']],
    output: 'Build successful: shapes',
  },
  { do: 'run', command: './shapes', argv: [['./shapes']], output: RAN_4 },
]

/**
 * What `axiom new hello` writes and what `axiom run` then prints inside
 * the project. `check-samples.mjs` runs both and compares.
 */
export const NEW_PROJECT = {
  name: 'hello',
  main: `(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "Hello from Axiom! 🚀")
    0
  })`,
  output: 'Hello from Axiom! 🚀',
}

/**
 * The tour: ten small real programs, one per idea, in the order a
 * newcomer needs them - from the thing every language has to the
 * things only this one does.
 */
export const TOUR: Program[] = [
  {
    id: "types",
    file: "parcels.ax",
    tab: "Types & matching",
    title: "Shipment status report",
    lede: "Sum types with named fields, matched exhaustively. `Option` is built in, so a missing value is a type rather than a null.",
    points: [
      { at: "(InTransit { carrier : String, days : Int })", text: "A constructor can carry named fields." },
      { at: "(:: alert (-> Parcel (Option String)))", text: "`alert` returns `Option String`, because some parcels need no action." },
      { at: "(a (optUnwrapOr (alert p) \"-\"))", text: "`optUnwrapOr` supplies the default where there is no value." },
      { at: "(println \"{id:<9}{s:<22}{a}\")", text: "`{id:<9}` pads to nine columns. Format strings are compiled, not interpreted at run time." },
    ],
    docs: { label: "Pattern matching", href: `${REF}#pattern-matching` },
    output: `parcel   status                action
AX-1041  packing               not shipped yet
AX-1042  DHL, 2 days out       -
AX-1043  held at customs       call about customs
AX-1044  delivered             -`,
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
    ((Delivered) "delivered")))

(:: alert (-> Parcel (Option String)))
(fn (alert p)
  (match p
    ((Ordered) (Some "not shipped yet"))
    ((InTransit _ _) None)
    ((Held why) (Some (format "call about {why}")))
    ((Delivered) None)))

(:: row (-> String Parcel Int))
;@axiom:effect(io)
(fn (row id p)
  (let (
    (s (status p))
    (a (optUnwrapOr (alert p) "-"))
  )
    (println "{id:<9}{s:<22}{a}")))

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
  })`,
  },
  {
    id: "records",
    file: "stock.ax",
    tab: "Records",
    title: "Restock the shelf",
    lede: "Structs are built positionally and read by name. A field is immutable unless it is declared `mut`, and any record prints without formatting code.",
    points: [
      { at: "(mut qty : Int)", text: "Mutability is declared per field." },
      { at: "(set item.qty (+ item.qty order))", text: "`set` writes a `mut` field in place." },
      { at: "(println \"{ordered:>4} ordered  {item}\")", text: "`{item}` prints the whole record." },
    ],
    docs: { label: "Structs", href: `${REF}#structs` },
    output: `   0 ordered  {sku = "bolt-m4", qty = 120, min = 50}
  88 ordered  {sku = "nut-m4", qty = 100, min = 50}
 400 ordered  {sku = "washer", qty = 400, min = 200}`,
    code: `(import IO)
(import Vec)

(struct Item
  (sku : String)
  (mut qty : Int)
  (min : Int))

(:: restock (-> Item Int))
(fn (restock item)
  (if (< item.qty item.min)
    (let ((order (- (* 2 item.min) item.qty)))
      {
        (set item.qty (+ item.qty order))
        order
      })
    0))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((shelf vecNew))
    {
      (vecPush shelf (Item "bolt-m4" 120 50))
      (vecPush shelf (Item "nut-m4" 12 50))
      (vecPush shelf (Item "washer" 0 200))
      (for item shelf
        (let ((ordered (restock item)))
          (println "{ordered:>4} ordered  {item}")))
      0
    }))`,
    refusal: {
      label: "Write a field that is not mut",
      note: "`min` was never declared `mut`, so writing it is refused, and the help says exactly where the declaration would change.",
      code: `(import IO)
(import Vec)

(struct Item
  (sku : String)
  (mut qty : Int)
  (min : Int))

(:: restock (-> Item Int))
(fn (restock item)
  (if (< item.qty item.min)
    (let ((order (- (* 2 item.min) item.qty)))
      {
        (set item.qty (+ item.qty order))
        (set item.min (+ item.min 10))
        order
      })
    0))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((shelf vecNew))
    {
      (vecPush shelf (Item "bolt-m4" 120 50))
      (vecPush shelf (Item "nut-m4" 12 50))
      (vecPush shelf (Item "washer" 0 200))
      (for item shelf
        (let ((ordered (restock item)))
          (println "{ordered:>4} ordered  {item}")))
      0
    }))`,
      human: `error[AX3012]: cannot assign to field \`min\` of \`Item\`: the field is not declared \`mut\`
  --> stock.ax:15:19
   |
15 |         (set item.min (+ item.min 10))
   |                   ^^^ \`min\` is not a \`mut\` field
   |
   = note: a struct field is immutable unless its declaration marks it \`mut\`, the rule \`let\` already follows; until 0.6.0 the marker was parsed and discarded and this store compiled in silence
   = help: declare it mutable where \`Item\` is defined: \`(mut min : Int)\`
   = help: run \`axiom explain AX3012\` for a full explanation

compilation failed due to 1 previous error`,
    },
  },
  {
    id: "failure",
    file: "settings.ax",
    tab: "Errors",
    title: "Three steps, one error path",
    lede: "Failure is a value. `Result` carries it, `try!` returns early on it, and `withContext` records which step failed.",
    points: [
      { at: "(withContext (okOr (strParseInt text) bad) (strConcat \"reading \" name))))", text: "`okOr` turns a missing number into an error with a message." },
      { at: "(withContext (mulChecked chunk parts) \"sizing the upload\"))", text: "`mulChecked` fails where `*` would wrap around." },
      { at: "(match (try! size (number \"chunk\" chunk)", text: "`try!` binds each success and stops at the first failure." },
    ],
    docs: { label: "The error model", href: `${LIB}docs/error-model.md` },
    output: `4096 x 256 = 1048576 bytes
4 KiB is not a number while reading chunk
product is not representable while sizing the upload`,
    code: `(import Err)
(import IO)
(import Str)

(:: number (-> String String (Result Int Error)))
(fn (number name text)
  (let ((bad (mkError 20 (strConcat text " is not a number"))))
    (withContext (okOr (strParseInt text) bad) (strConcat "reading " name))))

; \`*\` wraps silently on overflow; this is the one that can say no.
(:: upload (-> Int Int (Result Int Error)))
(fn (upload chunk parts)
  (withContext (mulChecked chunk parts) "sizing the upload"))

(:: report (-> String String Int))
;@axiom:effect(io)
(fn (report chunk parts)
  (match (try! size (number "chunk" chunk) (try! n (number "parts" parts) (upload size n)))
    ((Ok total) (println "{chunk} x {parts} = {total} bytes"))
    ((Err e) (println (errorText e)))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (report "4096" "256")
    (report "4 KiB" "256")
    (report "4096" "9007199254740993")
    0
  })`,
  },
  {
    id: "effects",
    file: "retry.ax",
    tab: "Effects",
    title: "Back-off you can test without sleeping",
    lede: "Declare an effect, perform it anywhere, and decide what it means where you call it. The same `retry` prints its plan under one handler and records its pauses under another, with no mocking framework.",
    points: [
      { at: "(pause :: (-> Int Int)))", text: "`Pause` declares one operation, `pause`." },
      { at: ";@axiom:effect(pause)", text: "`retry` says it performs `Pause`, and the compiler checks that it does." },
      { at: "(lambda (ms) (println \"pausing {ms} ms\")))", text: "In the program, a pause prints a line." },
      { at: "(lambda (ms) (vecLen (vecPush seen ms))))", text: "In the test, a pause is recorded, and nothing sleeps." },
    ],
    docs: { label: "Effects", href: `${REF}#effects` },
    output: `pausing 100 ms
pausing 200 ms
pausing 400 ms
test: 4 pauses recorded, 0 ms slept`,
    code: `(import IO)
(import Test)
(import Vec)

(effect Pause
  (pause :: (-> Int Int)))

; Exponential back-off: ask to pause 100 ms, then 200, 400 ...
; \`retry\` never learns what a pause is. Whoever handles Pause decides.
(:: retry (-> Int Int))
;@axiom:effect(pause)
(fn (retry attempts)
  (let ((mut delay 100))
    {
      (for i 0 attempts
        {
          (pause delay)
          (set delay (* delay 2))
        })
      attempts
    }))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((seen vecNew))
    {
      ; In the program: say what would happen.
      (handle
        (retry 3)
        (Pause)
        (lambda (ms) (println "pausing {ms} ms")))
      ; In a test: record the pauses as data, and sleep for none of them.
      (handle
        (retry 4)
        (Pause)
        (lambda (ms) (vecLen (vecPush seen ms))))
      (assertEq "four pauses" 4 (vecLen seen))
      (assertEq "doubling" 800 (vecGet seen 3))
      (println "test: 4 pauses recorded, 0 ms slept")
      0
    }))`,
  },
  {
    id: "collections",
    file: "inbox.ax",
    tab: "Collections",
    title: "Top words in a support inbox",
    lede: "`Vec`, `Map` and a string interner from the standard library, which is written in Axiom and calls no C.",
    points: [
      { at: "(for msg inbox", text: "`for` walks a `Vec` element by element." },
      { at: "(let ((id (internIntern words w)))", text: "Each word becomes an id, counted in a `Map`." },
      { at: "(byCount (lambda (a b)", text: "The comparator is a lambda that closes over the map." },
      { at: "(let ((ranked (vecSortBy (mapKeys count) byCount)))", text: "`vecSortBy` ranks the ids by count." },
    ],
    docs: { label: "Standard library", href: `${REF}#standard-library` },
    output: `   4  mobile
   3  payment
   3  safari
   3  checkout
   2  error`,
    code: `(import IO)
(import Intern)
(import Map)
(import Str)
(import Vec)

; "Safari." and "desktop," count as safari and desktop.
(:: bare (-> String String))
(fn (bare w)
  (let ((n (strLen w)))
    (if (strIsAlpha (strByte w (- n 1)))
      w
      (strSlice w 0 (- n 1)))))

; Each message is split on byte 32 (a space); each word of four
; letters or more is interned and counted, then the ids are ranked.
(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let (
    (inbox vecNew)
    (words internNew)
    (count mapNew)
    (byCount (lambda (a b) (- (mapGet count b 0) (mapGet count a 0))))
  )
    {
      (vecPush inbox "Checkout fails on mobile Safari.")
      (vecPush inbox "The payment sheet spins forever and never loads.")
      (vecPush inbox "Checkout works on desktop, but payment is greyed out on mobile.")
      (vecPush inbox "Payment declined with no error message on mobile Safari.")
      (vecPush inbox "Safari on iOS shows the same error.")
      (vecPush inbox "Checkout on mobile is unusable.")
      (for msg inbox
        (let ((parts (strSplit (strLower msg) 32)))
          (for i 0 (vecLen parts)
            (let ((w (bare (vecGet parts i))))
              (if (>= (strLen w) 4)
                (let ((id (internIntern words w)))
                  (mapInsert count id (+ 1 (mapGet count id 0))))
                0)))))
      (let ((ranked (vecSortBy (mapKeys count) byCount)))
        (for r 0 5
          (let (
            (id (vecGet ranked r))
            (n (mapGet count id 0))
            (w (internLookup words id))
          )
            (println "{n:>4}  {w}"))))
      0
    }))`,
  },
  {
    id: "concurrency",
    file: "triage.ax",
    tab: "Concurrency",
    title: "Sharded log triage",
    lede: "`parallel` runs each binding beside the caller and joins them in the order written: child processes by default, threads under `--threads`, the same output either way.",
    points: [
      { at: "(parallel scan (", text: "The three shards are scanned at once." },
      { at: "(let ((total (+ us (+ eu apac))))", text: "The body sees all three counts, joined in written order." },
      { at: "; A join carries one machine word", text: "Only a machine word crosses a join, and the compiler enforces it." },
    ],
    docs: { label: "parallel", href: `${REF}#run-expressions-side-by-side-with-parallel` },
    output: `errors  us 1  eu 2  apac 0  total 3`,
    code: `(import IO)
(import Str)

(:: errors (-> String Int Int))
(fn (errors shard from)
  (match (strFind shard "ERROR" from)
    ((None) 0)
    ((Some at) (+ 1 (errors shard (+ at 1))))))

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
      })))`,
    refusal: {
      label: "Share a string with a binding",
      note: "A binding that captures a reference the parent also holds is refused, under either lowering, because two threads touching one reference count could free memory still in use.",
      code: `(import IO)
(import Str)

(:: errors (-> String Int Int))
(fn (errors shard from)
  (match (strFind shard "ERROR" from)
    ((None) 0)
    ((Some at) (+ 1 (errors shard (+ at 1))))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((eu "ERROR db timeout\\nERROR cache miss\\nINFO up\\n"))
    (parallel scan (
      (us (errors "INFO up\\nERROR db timeout\\nWARN slow disk\\n" 0))
      (e (errors eu 0))
    )
      (let ((total (+ us e)))
        {
          (println "errors  us {us}  eu {e}  total {total}")
          0
        }))))`,
      human: `error[AX3064]: a concurrent binding captures \`eu\`, which has type \`String\` - a reference the parent also holds
  --> triage.ax:16:18
   |
16 |       (e (errors eu 0))
   |                  ^^ \`eu\` is bound outside this binding
   |
   = note: MM-PAR-6: a binding runs BESIDE its parent, and \`axiom_retain\`/\`axiom_release\` are a plain load-add-store rather than an \`atomicrmw\` - two threads touching one block's count lose an increment and free a block a live reference still names. The rule is the language's and not the lowering's, so it does not depend on \`--threads\`; \`__proc_spawn\` names the isolated lowering and is exempt
   = help: pass the value in through the thunk's word argument instead of capturing it, or build a copy of it inside the binding: what the binding may share with its parent is a word
   = help: run \`axiom explain AX3064\` for a full explanation

compilation failed due to 1 previous error`,
    },
  },
  {
    id: "regions",
    file: "requests.ax",
    tab: "Regions",
    title: "A million requests, one pointer move each",
    lede: "`(region r body)` resets the allocator when `body` ends, so everything a request built is reclaimed in one step. Only scalars may leave a region, and the compiler checks that.",
    points: [
      { at: "(region req", text: "Each request runs in its own region." },
      { at: "(set bytes (+ bytes (strLen (render id))))))", text: "The `Int` total leaves the region; the strings stay inside it." },
      { at: "(for id 0 1000000", text: "A million requests, and the heap ends where it began." },
    ],
    docs: { label: "Regions", href: `${REF}#regions` },
    output: `1000000 requests, 27818986 bytes rendered`,
    code: `(import IO)
(import Str)

; Stands in for real work: every call builds a fresh String.
(:: render (-> Int String))
(fn (render id)
  (format "GET /orders/{id} 200 {id:x}"))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((mut bytes 0))
    {
      (for id 0 1000000
        (region req
          (set bytes (+ bytes (strLen (render id))))))
      (println "1000000 requests, {bytes} bytes rendered")
      0
    }))`,
    refusal: {
      label: "Keep a string past its region",
      note: "Storing the rendered `String` in a variable outside the region would leave it pointing at reclaimed memory. The compiler refuses the store and the region answering it.",
      code: `(import IO)
(import Str)

; Stands in for real work: every call builds a fresh String.
(:: render (-> Int String))
(fn (render id)
  (format "GET /orders/{id} 200 {id:x}"))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((mut last ""))
    {
      (for id 0 1000000
        (region req
          (set last (render id))))
      (println "last request: {last}")
      0
    }))`,
      human: `error[AX3059]: \`last\` is bound outside region \`req\`, and the value stored into it has type \`String\`
  --> requests.ax:16:16
   |
16 |           (set last (render id))))
   |                ^^^^ this store leaves the region
   |
   = note: a store is the one escape channel a scope check can see; a call that stores the value for you is refused too, where the facts walk sees it
   = help: a reference allocated inside the region would outlive it: store a scalar, or bind the target inside the region
   = help: run \`axiom explain AX3059\` for a full explanation

error[AX3059]: region \`req\` answers a value of type \`String\`, which may point into the memory the region reclaims
  --> requests.ax:16:16
   |
16 |           (set last (render id))))
   |                ^^^^ this has type \`String\`
   |
   = note: a \`String\` is a descriptor over a second block, a struct is a block and a closure is a record; every one of them would point at reclaimed memory
   = help: answer a scalar - Int, Bool, Char, Float or Unit - which survives the reset by value; a reference has to be built outside the region until typed regions (docs/memory-model-v2-design.md §4, S3) can promote one
   = help: run \`axiom explain AX3059\` for a full explanation

compilation failed due to 2 previous errors`,
    },
  },
  {
    id: "macros",
    file: "quota.ax",
    tab: "Macros",
    title: "Storage quotas by plan",
    lede: "Macros rewrite the program tree before type checking, so what they generate is checked like code you wrote.",
    points: [
      { at: "(macro defUnit ((defUnit name factor)", text: "`defUnit` writes a signature and a function each time it is used." },
      { at: "((total x rest ...) (+ x (total rest ...))))", text: "`total` takes any number of terms, recursively." },
      { at: "(deriveEq Plan)", text: "`deriveEq` reads `Plan`'s constructors and writes `eqPlan`. No user code runs at compile time." },
    ],
    docs: { label: "Macros", href: `${REF}#macros` },
    output: `Free       536870912 bytes
Pro      21474836480 bytes
Team    129385889792 bytes  <- shared`,
    code: `(import IO)
(import Pre)

; A declaration macro: one line per unit writes a typed function.
(macro defUnit ((defUnit name factor)
   (:: name (-> Int Int))
   (fn (name n) (* n factor))))

(defUnit kib 1024)

(defUnit mib (kib 1024))

(defUnit gib (mib 1024))

; An expression macro whose last rule repeats: any number of terms.
(emacro total ((total x) x)
  ((total x rest ...) (+ x (total rest ...))))

(data Plan
  (Free)
  (Pro)
  (Team))

; Reads Plan's constructors at compile time and writes eqPlan.
(deriveEq Plan)

(:: quota (-> Plan Int))
(fn (quota p)
  (match p
    ((Free) (mib 512))
    ((Pro) (gib 20))
    ((Team) (total (gib 100) (gib 20) (mib 512)))))

(:: row (-> Plan Int))
;@axiom:effect(io)
(fn (row p)
  (let (
    (bytes (quota p))
    (mark (if (eqPlan p Team)
      "  <- shared"
      ""))
  )
    (println "{p:<6}{bytes:>14} bytes{mark}")))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (row Free)
    (row Pro)
    (row Team)
    0
  })`,
  },
  {
    id: "testing",
    file: "version.ax",
    tab: "Testing",
    title: "Version numbers, compared correctly",
    lede: "A test is a function whose name starts with `test`. `axiom test` finds them without registration, and a failed assertion ends only its own test.",
    points: [
      { at: "(fn (testComparesNumerically)", text: "The name is the registration." },
      { at: "(assertEq \"0.10.0 is newer\" 1 (versionCmp \"0.10.0\" \"0.9.4\")))", text: "Every assertion takes a label, so a failure says what it meant." },
    ],
    mode: 'test',
    docs: { label: "Testing", href: `${REF}#testing` },
    output: `ok   testComparesNumerically
ok   testEqualVersions
ok   testMissingPartIsZero
ok   testOlder

4 test(s), 0 failed`,
    code: `(import Str)
(import Test)
(import Vec)

; The i-th dotted part as a number; a missing part counts as 0.
(:: part (-> (Vec String) Int Int))
(fn (part parts i)
  (if (< i (vecLen parts))
    (optUnwrapOr (strParseInt (vecGet parts i)) 0)
    0))

; -1, 0 or 1. Numeric per part, so 0.10.0 is newer than 0.9.4,
; which comparing the strings would get backwards.
(:: versionCmp (-> String String Int))
(fn (versionCmp a b)
  (let (
    (pa (strSplit a 46))
    (pb (strSplit b 46))
    (mut i 0)
    (mut d 0)
  )
    {
      (while (&& (== d 0) (< i 3))
        {
          (set d (- (part pa i) (part pb i)))
          (set i (+ i 1))
        })
      (if (< d 0)
        -1
        (if (> d 0)
          1
          0))
    }))

(:: testComparesNumerically Int)
;@axiom:effect(io)
(fn (testComparesNumerically)
  (assertEq "0.10.0 is newer" 1 (versionCmp "0.10.0" "0.9.4")))

(:: testEqualVersions Int)
;@axiom:effect(io)
(fn (testEqualVersions)
  (assertEq "same version" 0 (versionCmp "0.7.6" "0.7.6")))

(:: testMissingPartIsZero Int)
;@axiom:effect(io)
(fn (testMissingPartIsZero)
  (assertEq "1.2 is 1.2.0" 0 (versionCmp "1.2" "1.2.0")))

(:: testOlder Int)
;@axiom:effect(io)
(fn (testOlder)
  (assertEq "older" -1 (versionCmp "1.9.9" "2.0.0")))`,
  },
  {
    id: "rust",
    file: "rusty.ax",
    tab: "Calling Rust",
    title: "Rust, one extern away",
    lede: "Mark Rust functions `#[axiom_export]` and `axiom-bindgen` writes the Axiom module for them. `--crate` builds the archive and links it.",
    points: [
      { at: "(loud (shout \"ships a binary\"))", text: "`shout` takes a borrowed string and returns an owned one." },
      { at: "(c (counterNew 40))", text: "`Counter` is an opaque Rust value behind a counted handle, dropped with its last reference." },
      { at: "(match (parseInt \"12x\")", text: "`parseInt` returns a Rust `Result`, matched like any Axiom one." },
    ],
    crate: "rust/examples/demo",
    docs: { label: "The FFI guide", href: `${LIB}docs/ffi.md` },
    output: `shout:   SHIPS A BINARY!
hypot:   5.0
counter: 42
Err:     invalid digit found in string`,
    code: `(import IO)
(import Demo)

; Demo is the module axiom-bindgen writes from the crate's
; #[axiom_export] functions; --crate builds and links its archive.
(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let (
    (loud (shout "ships a binary"))
    (h (hypot 3.0 4.0))
    (c (counterNew 40))
  )
    {
      (println "shout:   {loud}")
      (println "hypot:   {h:.1}")
      (counterAdd c 2)
      (let ((n (counterValue c)))
        (println "counter: {n}"))
      (match (parseInt "12x")
        ((Ok n) (println "parsed:  {n}"))
        ((Err why) (println "Err:     {why}")))
      0
    }))`,
    rust: {
      path: 'rust/examples/demo/src/lib.rs',
      code: `#[axiom_export]
pub fn hypot(x: f64, y: f64) -> f64 {
    (x * x + y * y).sqrt()
}

#[axiom_export]
pub fn shout(text: &str) -> String {
    let mut s = text.to_uppercase();
    s.push('!');
    s
}

#[axiom_export]
pub fn parse_int(text: &str) -> Result<i64, std::num::ParseIntError> {
    text.trim().parse::<i64>()
}

#[axiom_opaque]
pub struct Counter {
    n: i64,
}

#[axiom_export]
pub fn counter_new(start: i64) -> Counter {
    Counter { n: start }
}

#[axiom_export]
pub fn counter_value(c: &Counter) -> i64 {
    c.n
}

#[axiom_export]
pub fn counter_add(c: &mut Counter, by: i64) -> i64 {
    c.n = c.n.wrapping_add(by);
    c.n
}`,
    },
  },
]
