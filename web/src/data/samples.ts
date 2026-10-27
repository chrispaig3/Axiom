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
  /** `run` unless stated. A `serve` program is a server: it is shown as
   * `axiom run` and never exits on its own, so the checker drives
   * `client`'s session against it and then stops it with Ctrl-C. */
  mode?: 'run' | 'test' | 'serve'
  /** A `serve` program's client: the command shown, and each line sent
   * beside the line the server answers. Hanging up is Ctrl-D. */
  client?: { command: string; exchange: [string, string][] }
  /** Compiler options, placed before the input file. */
  flags?: string[]
  /** A Rust crate directory that `axiom-oxide prepare` builds. */
  crate?: string
  /** For a program that calls Rust: the crate side, quoted verbatim. */
  rust?: { path: string; code: string }
  refusal?: Refusal
  docs?: { label: string; href: string }
}

const LIB = 'https://github.com/chrispaig3/Axiom/blob/stable/'
const REF = `${LIB}docs/reference.md`

/** The shell commands that produced a program's output. */
export function commandFor(p: Program): string {
  const verb = p.mode === 'serve' ? 'run' : (p.mode ?? 'run')
  const command = `axiom ${verb}${p.flags?.length ? ` ${p.flags.join(' ')}` : ''} ${p.file}`
  if (!p.crate) return command
  return `axiom-oxide prepare --crate ${p.crate} --release\n` +
    `AXIOM_PATH=${p.crate}/axiom:pkg/axiom-oxide/axiom ` +
    `AXIOM_LINK_SEARCH=pkg/axiom-oxide/target/release ${command}`
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
  {
    (let a (area s))
    (println "{name:<10}{a:>8.2}")
  })

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (report "circle" (Circle 2.0))
    (report "rect" (Rect 3.0 4.5))
    (report "triangle" (Triangle 4.0 3.0))
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

(:: main ())
;@axiom:effect(io)
(fn (main)
  (println "Hello from Axiom! 🚀"))`,
  output: 'Hello from Axiom! 🚀',
}

/**
 * The tour: small real programs, one per idea, in the order a
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
      { at: "(let a (optUnwrapOr (alert p) \"-\"))", text: "`optUnwrapOr` supplies the default where there is no value." },
      { at: "(println \"{id:<9}{s:<17}{a}\")", text: "One row function aligns the header and data. `{id:<9}` pads to nine columns; the status column leaves two spaces after its longest value." },
    ],
    docs: { label: "Pattern matching", href: `${REF}#pattern-matching` },
    output: `parcel   status           action
AX-1041  packing          not shipped yet
AX-1042  DHL, 2 days out  -
AX-1043  held at customs  call about customs
AX-1044  delivered        -`,
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

(:: printRow (-> String String String ()))
;@axiom:effect(io)
(fn (printRow id s a)
  (println "{id:<9}{s:<17}{a}"))

(:: row (-> String Parcel ()))
;@axiom:effect(io)
(fn (row id p)
  {
    (let s (status p))
    (let a (optUnwrapOr (alert p) "-"))
    (printRow id s a)
  })

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (printRow "parcel" "status" "action")
    (row "AX-1041" Ordered)
    (row "AX-1042" (InTransit "DHL" 2))
    (row "AX-1043" (Held "customs"))
    (row "AX-1044" Delivered)
  })`,
  },
  {
    id: "numbers",
    file: "order.ax",
    tab: "Numbers & types",
    title: "Choose each number's representation",
    lede: "Fixed-width integers keep their precision. `as` makes conversions explicit, `type` gives an existing type a useful name, and `|>` reads a sequence of calls from left to right.",
    points: [
      { at: "(type Cents Int32)", text: "An alias is another name for its underlying type; it adds no conversion or new type." },
      { at: "(quantity : Quantity)", text: "This struct field uses UInt16's two bytes. Calls and container elements still use one machine word." },
      { at: "(* (as order.quantity Int32) order.unitPrice)", text: "Both operands must be Int32. The widening conversion is written explicitly." },
      { at: "(let amount (|> order total dollars))", text: "Each stage receives the previous result once. These unary stages are ordinary function calls." },
    ],
    docs: { label: "Fixed-width integers", href: `${REF}#fixed-width-integers` },
    output: "total: 37.50",
    code: `(import IO)

(type Quantity UInt16)

(type Cents Int32)

(struct Order
  (quantity : Quantity)
  (unitPrice : Cents))

(:: total (-> Order Cents))
(fn (total order)
  (* (as order.quantity Int32) order.unitPrice))

(:: dollars (-> Cents Float))
(fn (dollars cents)
  (/ (as cents Float) 100.0))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let order (Order :quantity (as 3 Quantity) :unitPrice (as 1250 Cents)))
    (let amount (|> order total dollars))
    (println "total: {amount:.2}")
  })`,
  },
  {
    id: "records",
    file: "stock.ax",
    tab: "Records",
    title: "Restock the shelf",
    lede: "Structs are built and read by field name. A field is immutable unless it is declared `mut`, and any record prints without formatting code.",
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
    {
      (let order (- (* 2 item.min) item.qty))
      {
        (set item.qty (+ item.qty order))
        order
      }
    }
    0))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let shelf vecNew)
    {
      (vecPush shelf (Item :sku "bolt-m4" :qty 120 :min 50))
      (vecPush shelf (Item :sku "nut-m4" :qty 12 :min 50))
      (vecPush shelf (Item :sku "washer" :qty 0 :min 200))
      (for item in shelf
        {
          (let ordered (restock item))
          (println "{ordered:>4} ordered  {item}")
        })
    }
  })`,
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
    {
      (let order (- (* 2 item.min) item.qty))
      {
        (set item.qty (+ item.qty order))
        (set item.min (+ item.min 10))
        order
      }
    }
    0))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let shelf vecNew)
    {
      (vecPush shelf (Item :sku "bolt-m4" :qty 120 :min 50))
      (vecPush shelf (Item :sku "nut-m4" :qty 12 :min 50))
      (vecPush shelf (Item :sku "washer" :qty 0 :min 200))
      (for item in shelf
        {
          (let ordered (restock item))
          (println "{ordered:>4} ordered  {item}")
        })
    }
  })`,
      human: `error[AX3012]: cannot assign to field \`min\` of \`Item\`: the field is not declared \`mut\`
  --> stock.ax:16:19
   |
16 |         (set item.min (+ item.min 10))
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
    lede: "Failure is a value. `Result` carries it, `?` hands it back, and `withContext` records which step failed.",
    points: [
      { at: "(withContext (okOr (strParseInt text) bad) (concat \"reading \" name))", text: "`okOr` turns a missing number into an error with a message." },
      { at: "(withContext (mulChecked chunk parts) \"sizing the upload\"))", text: "`mulChecked` fails where `*` would wrap around." },
      { at: "(let size (number \"chunk\" chunk)?)", text: "`?` binds each success and stops at the first failure." },
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
  {
    (let bad (mkError 20 (concat text " is not a number")))
    (withContext (okOr (strParseInt text) bad) (concat "reading " name))
  })

; \`*\` wraps silently on overflow; this is the one that can say no.
(:: upload (-> Int Int (Result Int Error)))
(fn (upload chunk parts)
  (withContext (mulChecked chunk parts) "sizing the upload"))

(:: sized (-> String String (Result Int Error)))
(fn (sized chunk parts)
  {
    (let size (number "chunk" chunk)?)
    (let n (number "parts" parts)?)
    (upload size n)
  })

(:: report (-> String String Int))
;@axiom:effect(io)
(fn (report chunk parts)
  (match (sized chunk parts)
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
  {
    (let mut delay 100)
    {
      (for i in 0..attempts
        {
          (pause delay)
          (set delay (* delay 2))
        })
      attempts
    }
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (let seen vecNew)
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
    }
  })`,
  },
  {
    id: 'contracts',
    file: 'contracts.ax',
    tab: 'Contracts',
    title: 'Check both sides of a call',
    lede: 'State what your function accepts and what it promises. Every call checks both clauses.',
    points: [
      { at: ';@axiom:pre((<= lo hi))', text: '`pre` checks the bounds before the function runs.' },
      { at: ';@axiom:post((&& (>= result lo) (<= result hi)))', text: '`post` reads the returned value as `result`. A failed clause traps with status 80.' },
    ],
    code: `(import IO)

;@axiom:pre((<= lo hi))
;@axiom:post((&& (>= result lo) (<= result hi)))
(:: clamp (-> Int Int Int Int))
(fn (clamp n lo hi)
  (if (< n lo)
    lo
    (if (> n hi)
      hi
      n)))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let below (clamp -3 0 10))
    (let inside (clamp 7 0 10))
    (let above (clamp 18 0 10))
    (println "{below} {inside} {above}")
  })`,
    output: '0 7 10',
    docs: { label: 'Contracts', href: `${REF}#contracts-pre-and-post` },
  },
  {
    id: "collections",
    file: "inbox.ax",
    tab: "Collections",
    title: "Top words in a support inbox",
    lede: "`Vec`, `Map` and a string interner from the standard library, which is written in Axiom and calls no C.",
    points: [
      { at: "(for msg in inbox", text: "`for` walks a `Vec` element by element." },
      { at: "(let id (internIntern words w))", text: "Each word becomes an id, counted in a `Map`. The interner owns its bytes; look them up while it is live." },
      { at: "(let byCount (lambda (a b)", text: "The comparator is a lambda that closes over the map." },
      { at: "(let ranked (vecSortBy (mapKeys count) byCount))", text: "`vecSortBy` ranks the ids by count." },
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
  {
    (let n (strLen w))
    (if (strIsAlpha (strByte w (- n 1)))
      w
      (strSlice w 0 (- n 1)))
  })

; Each message is split on byte 32 (a space); each word of four
; letters or more is interned and counted, then the ids are ranked.
(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let inbox vecNew)
    (let words internNew)
    (let count mapNew)
    (let byCount (lambda (a b) (- (mapGet count b 0) (mapGet count a 0))))
    {
      (vecPush inbox "Checkout fails on mobile Safari.")
      (vecPush inbox "The payment sheet spins forever and never loads.")
      (vecPush inbox "Checkout works on desktop, but payment is greyed out on mobile.")
      (vecPush inbox "Payment declined with no error message on mobile Safari.")
      (vecPush inbox "Safari on iOS shows the same error.")
      (vecPush inbox "Checkout on mobile is unusable.")
      (for msg in inbox
        {
          (let parts (strSplit (strLower msg) 32))
          (for i in 0..(vecLen parts)
            {
              (let w (bare (vecGet parts i)))
              (if (>= (strLen w) 4)
                {
                  (let id (internIntern words w))
                  (mapInsert count id (+ 1 (mapGet count id 0)))
                }
                0)
            })
        })
      {
        (let ranked (vecSortBy (mapKeys count) byCount))
        (for r in 0..5
          {
            (let id (vecGet ranked r))
            (let n (mapGet count id 0))
            (let w (internLookup words id))
            (println "{n:>4}  {w}")
          })
      }
    }
  })`,
  },
  {
    id: "concurrency",
    file: "triage.ax",
    tab: "Concurrency",
    title: "Sharded log triage",
    lede: "`parallel` runs each binding beside the caller and joins them in the order written: child processes by default, threads under `--threads`, the same output either way.",
    points: [
      { at: "(parallel scan (", text: "The three shards are scanned at once." },
      { at: "(nus (errors us 0))", text: "Each binding borrows its shard: the string's count is frozen until the last join, so no binding's retain or release reaches it." },
      { at: ";@axiom:effect(spawn)", text: "`main` declares `spawn` and `block`: its bindings start beside it, and it waits for them." },
      { at: "(let total (+ nus (+ neu napac)))", text: "The body sees all three counts, joined in written order." },
      { at: "; Each binding borrows its shard", text: "What comes back across a join is one machine word, and the compiler enforces it." },
    ],
    docs: { label: "parallel", href: `${REF}#what-a-binding-may-capture` },
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
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  ; Each binding borrows its shard, and a join carries one word back.
  {
    (let us "INFO up\\nERROR db timeout\\nWARN slow disk\\n")
    (let eu "ERROR db timeout\\nERROR cache miss\\nINFO up\\n")
    (let apac "INFO up\\nWARN slow disk\\nINFO up\\n")
    (parallel scan (
      (nus (errors us 0))
      (neu (errors eu 0))
      (napac (errors apac 0))
    )
      {
        (let total (+ nus (+ neu napac)))
        {
          (println "errors  us {nus}  eu {neu}  apac {napac}  total {total}")
          0
        }
      })
  })`,
    refusal: {
      label: "Share a growing list with a binding",
      note: "A binding may borrow a `String`, but not a `Vec`: two bindings could grow one buffer at once. The capture is refused under either lowering.",
      code: `(import IO)
(import Vec)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  {
    (let seen (:: vecNew (Vec Int)))
    (parallel scan (
      (us (vecLen (vecPush seen 1)))
      (eu 2)
    )
      (+ us eu))
  })`,
      human: `error[AX3064]: a concurrent binding captures \`seen\`, which has type \`Vec Int\` - a mutable container the parent also holds, which a binding could grow while another reads it
  --> triage.ax:12:28
   |
12 |       (us (vecLen (vecPush seen 1)))
   |                            ^^^^ \`seen\` is bound outside this binding
   |
   = note: MM-PAR-6: a binding runs BESIDE its parent, and \`axiom_retain\`/\`axiom_release\` are a plain load-add-store rather than an \`atomicrmw\` - two threads touching one block's count lose an increment and free a block a live reference still names. The rule is the language's and not the lowering's, so it does not depend on \`--threads\`; \`__proc_spawn\` names the isolated lowering and is exempt
   = help: pass the value in through the thunk's word argument instead of capturing it, or build a copy of it inside the binding. A \`parallel\` binding may borrow a String or an immutable data graph its parent holds. Mutable, unknown and type-changing recursive payloads cannot be borrowed; the structural check examines at most 64 nested types. Use a shared word handle or explicit serialization for other input
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
      { at: "(for id in 0..1000000", text: "A million requests, and the heap ends where it began." },
    ],
    docs: { label: "Regions", href: `${REF}#regions` },
    output: `1000000 requests, 27818986 bytes rendered`,
    code: `(import IO)
(import Str)

; Stands in for real work: every call builds a fresh String.
(:: render (-> Int String))
(fn (render id)
  (format "GET /orders/{id} 200 {id:x}"))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let mut bytes 0)
    {
      (for id in 0..1000000
        (region req
          (set bytes (+ bytes (strLen (render id))))))
      (println "1000000 requests, {bytes} bytes rendered")
    }
  })`,
    refusal: {
      label: "Keep a string past its region",
      note: "Storing the rendered `String` in a variable outside the region would leave it pointing at reclaimed memory. The compiler refuses the store and the region answering it.",
      code: `(import IO)
(import Str)

; Stands in for real work: every call builds a fresh String.
(:: render (-> Int String))
(fn (render id)
  (format "GET /orders/{id} 200 {id:x}"))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let mut last "")
    {
      (for id in 0..1000000
        (region req
          (set last (render id))))
      (println "last request: {last}")
    }
  })`,
      human: `error[AX3059]: \`last\` is bound outside region \`req\`, and the value stored into it has type \`String\`
  --> requests.ax:17:16
   |
16 |         (region req
   |                 --- this region ends before the outer binding is used
17 |           (set last (render id))))
   |                ^^^^ this store leaves the region
   |
   = note: a store is the one escape channel a scope check can see; a call that stores the value for you is refused too, where the facts walk sees it
   = help: move the reference allocation and this store outside the region, or bind the destination inside it; an outer binding may receive a scalar computed inside the region
   = help: run \`axiom explain AX3059\` for a full explanation

error[AX3059]: region \`req\` answers a value of type \`String\`, which may point into the memory the region reclaims
  --> requests.ax:17:16
   |
16 |         (region req
   |                 --- this region reclaims the result's allocation when its body ends
17 |           (set last (render id))))
   |                ^^^^ this has type \`String\`
   |
   = note: a \`String\` is a descriptor over a second block, a struct is a block and a closure is a record; every one of them would point at reclaimed memory
   = help: compute a scalar such as (strLen value) inside the region and return it; if you need a reference result, allocate it outside the region
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
(macro total ((total x) x)
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
  {
    (let bytes (quota p))
    (let mark
      (if (eqPlan p Team)
        "  <- shared"
        ""))
    (println "{p:<6}{bytes:>14} bytes{mark}")
  })

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (row Free)
    (row Pro)
    (row Team)
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
  {
    (let pa (strSplit a 46))
    (let pb (strSplit b 46))
    (let mut i 0)
    (let mut d 0)
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
    }
  })

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
    id: 'json',
    file: 'payload.ax',
    tab: 'Cereal',
    title: 'Read TOML, check a field, write JSON',
    lede: '`Cereal` decodes JSON, TOML and YAML into one typed value. A codec reads each field, and a missing or mistyped one is an error that names it.',
    points: [
      { at: '(cerealDecode CerealToml toml)', text: 'Decoding returns a Result, and `?` hands an error straight back.' },
      { at: '(cerealField cerealIntCodec config "replicas")', text: 'A missing or non-integer field is an Error naming replicas.' },
      { at: '(cerealEncode CerealJson config)', text: 'The same value writes out as JSON, TOML or YAML.' },
    ],
    docs: { label: 'Cereal and RPC framing', href: `${LIB}docs/stdlib.md#cereal` },
    output: `{"name":"payments","replicas":3}`,
    code: `(import IO)
(import Err)
(import Cereal)

(:: toJson (-> String (Result String Error)))
(fn (toJson toml)
  {
    (let config (cerealDecode CerealToml toml)?)
    (let replicas (cerealField cerealIntCodec config "replicas")?)
    (if (< replicas 1)
      (Err (mkError 22 "replicas must be at least 1"))
      (cerealEncode CerealJson config))
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (toJson "name = \\"payments\\"\\nreplicas = 3\\n")
    ((Err e) (die (errorText e) 1))
    ((Ok json)
      {
        (println json)
        0
      }
    )))`,
  },
  {
    id: 'tcp',
    file: 'echo.ax',
    tab: 'TCP',
    title: 'An echo server that runs until you stop it',
    lede: '`Net` is TCP the way Rust\'s `std::net` has it. This server answers each line a client sends with the same line, serves one client after another, and runs until you press Ctrl-C. Try it with `nc` in a second terminal.',
    points: [
      { at: '(match (tcpReadLine conn 4096)', text: 'One line without its newline, capped at 4 KiB so a client cannot grow your memory without bound.' },
      { at: '((Ok (None)) 0)', text: 'None means the client hung up. When serve returns, the connection closes itself and the loop takes the next client.' },
      { at: '(while true', text: 'The accept loop never returns: the server runs until you stop it.' },
    ],
    docs: { label: 'TCP with Net', href: `${LIB}docs/stdlib.md#net` },
    mode: 'serve',
    client: {
      command: 'nc 127.0.0.1 7878',
      exchange: [
        ['hello', 'hello'],
        ['still here?', 'still here?'],
      ],
    },
    output: 'listening on 127.0.0.1:7878',
    code: `(import Err)
(import IO)
(import Net)
(import Str)

(:: report (-> String Error Int))
;@axiom:effect(io)
(fn (report what e)
  {
    (let why (errorText e))
    (eprintln "{what}: {why}")
  })

; Echo each line back until the client hangs up.
(:: serve (-> TcpStream Int))
;@axiom:effect(io)
(fn (serve conn)
  (match (tcpReadLine conn 4096)
    ((Ok (Some line))
      (match (tcpWrite conn (concat line "\\n"))
        ((Ok _) (serve conn))
        ((Err e) (report "write" e)))
    )
    ((Ok (None)) 0)
    ((Err e) (report "read" e))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (tcpListen "127.0.0.1:7878")
    ((Err e) (report "listen" e))
    ((Ok lsn)
      {
        (println "listening on 127.0.0.1:7878")
        (while true
          (match (tcpAccept lsn)
            ((Ok conn) (serve conn))
            ((Err e) (report "accept" e))))
        0
      }
    )))`,
  },
  {
    id: 'chrono',
    file: 'schedule.ax',
    tab: 'Dates & times',
    title: 'Normalise a timestamp, then add a duration',
    lede: '`Chrono` validates calendar values and returns a Result for parsing and arithmetic. An offset-bearing timestamp can be normalised to UTC; the returned date-time holds no zone field.',
    points: [
      { at: '(let start (datetimeParseUtc "2024-02-29T23:30:00+02:00")?)', text: 'The +02:00 offset is applied before the naive UTC date-time is returned.' },
      { at: '(let delay (durationParse "PT1H30M")?)', text: '`?` binds each success and propagates an error at either step.' },
      { at: '(datetimeAdd start delay)', text: 'Duration arithmetic refuses results outside the supported range.' },
    ],
    docs: { label: 'Dates and times', href: `${LIB}docs/chrono.md` },
    output: '2024-02-29T23:00:00',
    code: `(import Chrono)
(import Err)
(import IO)

(:: arrival (Result NaiveDateTime Error))
(fn (arrival)
  {
    (let start (datetimeParseUtc "2024-02-29T23:30:00+02:00")?)
    (let delay (durationParse "PT1H30M")?)
    (datetimeAdd start delay)
  })

(:: main ())
;@axiom:effect(io)
(fn (main)
  (match arrival
    ((Err e) (die (errorText e) 1))
    ((Ok end) (println (datetimeToString end)))))`,
  },
  {
    id: 'tasks',
    file: 'jobs.ax',
    tab: 'Task pools',
    title: 'Bound the workers, keep submit order',
    lede: '`Task` runs jobs in forked children, limits concurrency and answer size, then returns one Result per job in submit order. Options add deadlines, cancellation and fail-fast behaviour.',
    points: [
      { at: '(let answers (taskMap job 4 2 64))', text: 'Four jobs, at most two running at once, with at most 64 bytes in each answer.' },
      { at: '(for answer in answers', text: 'Answers keep submit order even when workers finish in a different order.' },
      { at: '((Err e) (println (errorText e)))', text: 'A failed job has an error value in its own slot.' },
    ],
    docs: { label: 'Task pools and streaming folds', href: `${REF}#run-tasks-that-answer-values-with-task` },
    output: `job 0: 0
job 1: 1
job 2: 4
job 3: 9`,
    code: `(import Err)
(import IO)
(import Task)
(import Vec)

(:: job (-> Int String))
(fn (job i)
  {
    (let square (* i i))
    (format "job {i}: {square}")
  })

(:: main ())
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  {
    (let answers (taskMap job 4 2 64))
    (for answer in answers
      (match answer
        ((Ok text) (println text))
        ((Err e) (println (errorText e)))))
  })`,
  },
  {
    id: 'obfuscation',
    file: 'asset.ax',
    tab: 'Asset protection',
    flags: ['--obfuscate'],
    title: 'Authenticate an embedded asset',
    lede: '`Crypto.Obfuscate` seals bytes with a fresh nonce and a context-bound key. Use the packing tool before compilation, and optional --obfuscate for literal masking and internal symbols. Running-process inspection can still recover embedded data.',
    points: [
      { at: '(let envelope (obfuscationSeal key "demo/message/v1" "asset opened")?)', text: 'A context identifies the asset purpose and is authenticated with its bytes.' },
      { at: '(obfuscationOpen key "demo/message/v1" envelope)', text: 'Open verifies the tag before returning plaintext.' },
      { at: '(obfuscationKeyWipe key)', text: 'Erase the key on both success and error before examining the Result.' },
    ],
    docs: { label: 'Pack assets and obfuscate executables', href: `${LIB}docs/obfuscation.md` },
    output: 'asset opened',
    code: `(import Crypto.Obfuscate)
(import Err)
(import IO)

(:: roundTrip (-> ObfuscationKey (Result String Error)))
;@axiom:effect(io)
;@axiom:effect(entropy)
(fn (roundTrip key)
  {
    (let envelope (obfuscationSeal key "demo/message/v1" "asset opened")?)
    (obfuscationOpen key "demo/message/v1" envelope)
  })

(:: main ())
;@axiom:effect(io)
;@axiom:effect(entropy)
(fn (main)
  (match obfuscationKeyGenerate
    ((Err e) (die (errorText e) 1))
    ((Ok key)
      {
        (let opened (roundTrip key))
        {
          (obfuscationKeyWipe key)
          (match opened
            ((Err e) (die (errorText e) 1))
            ((Ok text) (println text)))
        }
      }
    )))`,
  },
  {
    id: "rust",
    file: "rusty.ax",
    tab: "Calling Rust",
    title: "Rust, one extern away",
    lede: "Mark Rust functions `#[axiom_export]` and `axiom-oxide prepare` writes their Axiom module and builds the archive. This caller vouches for the direct scalar extern call with `effect(unsafe)`.",
    points: [
      { at: "(let loud (shout \"ships a binary\"))", text: "`shout` takes a borrowed string and returns an owned one." },
      { at: "(let c (counterNew 40))", text: "`Counter` is an opaque Rust value behind a counted handle, dropped with its last reference." },
      { at: "(match (parseInt \"12x\")", text: "`parseInt` returns a Rust `Result`, matched like any Axiom one." },
    ],
    crate: "pkg/axiom-oxide/examples/demo",
    docs: { label: "The FFI guide", href: `${LIB}docs/ffi.md` },
    output: `shout:   SHIPS A BINARY!
hypot:   5.0
counter: 42
Err:     invalid digit found in string`,
    code: `(import IO)
(import Demo)

; Demo is the module axiom-bindgen writes from the crate's
; #[axiom_export] functions; axiom-oxide prepare builds its archive.
(:: main ())
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  {
    (let loud (shout "ships a binary"))
    (let h (hypot 3.0 4.0))
    (let c (counterNew 40))
    {
      (println "shout:   {loud}")
      (println "hypot:   {h:.1}")
      (counterAdd c 2)
      {
        (let n (counterValue c))
        (println "counter: {n}")
      }
      (match (parseInt "12x")
        ((Ok n) (println "parsed:  {n}"))
        ((Err why) (println "Err:     {why}")))
    }
  })`,
    rust: {
      path: 'pkg/axiom-oxide/examples/demo/src/lib.rs',
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
