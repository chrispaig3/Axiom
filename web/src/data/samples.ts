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
 *     its commands shows.
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
  refusal?: Refusal
  docs?: { label: string; href: string }
}

const LIB = 'https://github.com/chrispaig3/Axiom/blob/stable/'
const REF = `${LIB}docs/reference.md`

/** The shell commands that produced a program's output. */
export function commandFor(p: Program): string {
  return `axiom run ${p.file}`
}

/**
 * The program the landing demo types first: it writes a small folder,
 * runs the system `ls` on it through `Sys`, and classifies what came
 * back - a sum type, an exhaustive match, functions that promise no
 * I/O, and ones that declare the processes they start. Checked on its
 * own as well as in the demo.
 */
export const HERO: Program = {
  id: 'files',
  file: 'files.ax',
  tab: 'files.ax',
  title: 'A whole program',
  lede: '',
  points: [],
  output: `source code.ax
docs   notes.md
text   readme.txt`,
  code: `(import Err)
(import IO)
(import Path)
(import Str)
(import Sys)
(import Vec)

(data Kind
  (Source)
  (Docs)
  (Text))

(:: kind (-> String Kind))
;@axiom:restrict(no-io)
(fn (kind name)
  {
    (let ext (pathExt name))
    (if (strEq ext ".ax")
        Source
      (strEq ext ".md")
        Docs
      Text)
  })

(:: label (-> Kind String))
;@axiom:restrict(no-io)
(fn (label k)
  (match k
    ((Source) "source")
    ((Docs) "docs")
    ((Text) "text")))

; A folder to look at, rebuilt the same way on every run.
(:: setup ())
;@axiom:effect(io)
(fn (setup)
  {
    (let _ (makeDir "crate"))
    (let _ (writeFile "crate/code.ax" "code\\n"))
    (let _ (writeFile "crate/notes.md" "notes\\n"))
    (let _ (writeFile "crate/readme.txt" "readme\\n"))
  })

; Run ls on the folder and read back what it printed.
(:: listing (Result String Error))
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (listing)
  {
    (let args vecNew)
    (vecPush args "ls")
    (vecPush args "crate")
    (let pid (sysSpawnOutErrTo "/bin/ls" args "ls.out" "ls.err")?)
    (let status (sysWaitPid pid)?)
    (if (== (sysExitCode status) 0)
      (readFile "ls.out")
      (Err (mkError 1 "ls failed")))
  })

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  {
    (setup)
    (match listing
      ((Err e)
        {
          (println (errorText e))
          1
        }
      )
      ((Ok text)
        {
          (let names (strSplit text 10))
          {
            (for name in names
              (if (! (strIsEmpty name))
                {
                  (let tag (label (kind name)))
                  (println "{tag:<7}{name}")
                }))
            0
          }
        }
      ))
  })`,
}

/**
 * The landing demo: a script, not a recording.
 *
 * The page plays it as a terminal session - `files.ax` typed into an
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
export const DEMO_FILE = 'files.ax'

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

const [TYPES, CLASSIFY, REST] = cut(HERO.code, '(:: kind', '(:: setup') as [string, string, string]

const RAN = `source code.ax
docs   notes.md
text   readme.txt`

const RAN_4 = `source code.ax
data   data.csv
docs   notes.md
text   readme.txt`

export const DEMO: DemoStep[] = [
  { do: 'chapter', name: 'write' },
  { do: 'say', text: 'A sum type: the three kinds of file a listing can hold.' },
  { do: 'type', text: TYPES },
  { do: 'say', text: '`kind` and `label` only look at a name, so both promise no I/O - and the compiler holds them to it.' },
  { do: 'type', text: CLASSIFY },
  { do: 'say', text: 'The rest talks to the system: write a folder, run `ls` on it through `Sys`, and read its output back.' },
  { do: 'type', text: REST },

  { do: 'chapter', name: 'run' },
  { do: 'say', text: 'Compile and run in one step. No build file.' },
  { do: 'run', command: `axiom run ${DEMO_FILE}`, argv: [['run', DEMO_FILE]], output: RAN },
  { do: 'wait', ms: 1400 },

  { do: 'chapter', name: 'break' },
  { do: 'say', text: 'Add a fourth kind, and nothing else.' },
  { do: 'after', text: '  (Docs)' },
  { do: 'type', text: '\n  (Data)' },
  { do: 'say', text: 'The `match` in `label` no longer covers every kind. The compiler names it, and the missing arm.' },
  {
    do: 'run',
    command: `axiom check ${DEMO_FILE}`,
    argv: [['check', DEMO_FILE]],
    exit: 1,
    output: `error[AX3005]: non-exhaustive pattern match: missing Data
  --> files.ax:29:10
   |
29 |   (match k
   |          ^ this \`match\` does not cover: Data
   |
   = help: add the missing arms, each a \`todo\` until it is written ~>
               ((Data) (todo "Data"))
   = help: run \`axiom explain AX3005\` for a full explanation

compilation failed due to 1 previous error`,
  },
  { do: 'wait', ms: 3600 },

  { do: 'chapter', name: 'fix' },
  { do: 'say', text: 'Label the new kind, recognise `.csv`, and put one in the folder.' },
  { do: 'after', text: '((Text) "text")' },
  { do: 'type', text: '\n    ((Data) "data")' },
  { do: 'after', text: '(strEq ext ".md")\n        Docs' },
  { do: 'type', text: '\n      (strEq ext ".csv")\n        Data' },
  { do: 'after', text: '(let _ (writeFile "crate/readme.txt" "readme\\n"))' },
  { do: 'type', text: '\n    (let _ (writeFile "crate/data.csv" "data\\n"))' },
  { do: 'run', command: `axiom run ${DEMO_FILE}`, argv: [['run', DEMO_FILE]], output: RAN_4 },
  { do: 'wait', ms: 1400 },

  { do: 'chapter', name: 'ship' },
  { do: 'say', text: 'A native executable, with its allocator and syscalls inside it.' },
  {
    do: 'run',
    command: `axiom build ${DEMO_FILE} -o files`,
    argv: [['build', DEMO_FILE, '-o', 'files']],
    output: 'Build successful: files',
  },
  { do: 'run', command: './files', argv: [['./files']], output: RAN_4 },
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
 * The tour: five whole programs, each doing one job end to end, in
 * the order a newcomer's questions arrive - how values, records and
 * failures work, how the standard library carries real work, and
 * the two things only this language does.
 */
export const TOUR: Program[] = [
  {
    id: "checkout",
    file: "orders.ax",
    tab: "Checkout",
    title: "Price a basket; discount it by the first offer that applies",
    lede: "One program doing one job end to end: parse order lines into typed records, total them in exact cents, then pick a discount. Failure is a `Result`, every conversion is written out, and the offer choice is a single `if let` chain.",
    points: [
      { at: "(let qty (number \"qty\" (vecGet parts 1))?)", text: "`?` binds each parsed number and hands the first failure back with the context that names it - the last line of output is that path." },
      { at: "(mut qty : Quantity)", text: "`qty` is `UInt16` under the alias `Quantity`, `unit` is `Int32` cents, and `as` converts between them explicitly. `mut` is per field, so `topUp` may rewrite `qty` and nothing else." },
      { at: "(if (let (Some pct) coupon)", text: "An `if let` chain mixing pattern tests with a plain `Bool`: a coupon first, else loyalty points, else 5% over a hundred dollars, else nothing." },
      { at: ";@axiom:post((&& (>= result lo) (<= result hi)))", text: "Contracts on the clamp: `pre` checks the bounds before the call, `post` reads the answer as `result`. Both run at every call." },
      { at: "(macro sum3 ((sum3 a b c) (+ a (+ b c))))", text: "Macros rewrite the program tree before type checking, so what `sum3` expands to is checked like code you wrote." },
    ],
    docs: { label: "if let", href: `${REF}#if-let` },
    output: `subtotal 57.50, discount 24%, total 43.70
subtotal 57.50, discount 10%, total 51.75
subtotal 120.00, discount 5%, total 114.00
two is not a number while reading qty`,
    code: `(import Err)
(import IO)
(import Str)
(import Vec)

(type Quantity UInt16)

(type Cents Int32)

(struct Line
  (sku : String)
  (mut qty : Quantity)
  (unit : Cents))

; An expression macro: it rewrites the call into two additions
; before type checking, so the sum is checked like handwritten code.
(macro sum3 ((sum3 a b c) (+ a (+ b c))))

(:: number (-> String String (Result Int Error)))
(fn (number name text)
  {
    (let bad (mkError 20 (concat text " is not a number")))
    (withContext (okOr (strParseInt text) bad) (concat "reading " name))
  })

; Lines arrive as "sku qty unit-cents". \`?\` binds each number and
; stops at the first one that is not there.
(:: parseLine (-> String (Result Line Error)))
(fn (parseLine text)
  {
    (let parts (strSplit text 32))
    (let qty (number "qty" (vecGet parts 1))?)
    (let unit (number "price" (vecGet parts 2))?)
    (Ok (Line :sku (vecGet parts 0) :qty (as qty Quantity) :unit (as unit Cents)))
  })

; Nothing ships singly: a line for one becomes a line for two.
; \`set\` can write qty because the field is declared \`mut\`.
(:: topUp (-> Line ()))
(fn (topUp line)
  (if (< (as line.qty Int) 2)
    (set line.qty (as 2 Quantity))))

(:: lineTotal (-> Line Cents))
(fn (lineTotal line)
  (* (as line.qty Int32) line.unit))

;@axiom:pre((<= lo hi))
;@axiom:post((&& (>= result lo) (<= result hi)))
(:: clampPct (-> Int Int Int Int))
(fn (clampPct pct lo hi)
  (if (< pct lo)
    lo
    (if (> pct hi)
      hi
      pct)))

; The discount, in the order offers are considered: a coupon if there
; is one, else loyalty points (a percent per ten, capped at 30), else
; 5% over a hundred dollars, else nothing. One \`if\` chain, mixing
; pattern tests with an ordinary Bool test.
(:: discount (-> (Option Int) (Option Int) Cents Int))
(fn (discount coupon loyalty subtotal)
  (if (let (Some pct) coupon)
      pct
    (let (Some points) loyalty)
      (clampPct (/ points 10) 0 30)
    (> subtotal (as 10000 Cents))
      5
    0))

(:: dollars (-> Cents Float))
(fn (dollars cents)
  (/ (as cents Float) 100.0))

(:: checkout (-> String String String (Option Int) (Option Int) (Result String Error)))
(fn (checkout a b c coupon loyalty)
  {
    (let first (parseLine a)?)
    (let second (parseLine b)?)
    (let third (parseLine c)?)
    {
      (topUp first)
      (topUp second)
      (topUp third)
    }
    (let subtotal (sum3 (lineTotal first) (lineTotal second) (lineTotal third)))
    (let pct (discount coupon loyalty subtotal))
    (let off (/ (* subtotal (as pct Cents)) (as 100 Cents)))
    (let due (- subtotal off))
    (let before (dollars subtotal))
    (let after (dollars due))
    (Ok (format "subtotal {before:.2}, discount {pct}%, total {after:.2}"))
  })

(:: report (-> String String String (Option Int) (Option Int) ()))
;@axiom:effect(io)
(fn (report a b c coupon loyalty)
  (match (checkout a b c coupon loyalty)
    ((Ok text) (println text))
    ((Err e) (println (errorText e)))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (report "bolt-m4 3 1250" "nut-m4 4 250" "washer 1 500" None (Some 240))
    (report "bolt-m4 3 1250" "nut-m4 4 250" "washer 1 500" (Some 10) (Some 240))
    (report "bolt-m4 8 1250" "nut-m4 4 250" "washer 1 500" None None)
    (report "bolt-m4 3 1250" "nut-m4 two 250" "washer 1 500" None (Some 240))
  })`,
    refusal: {
      label: "Rename a line's sku in place",
      note: "`sku` was never declared `mut`, so writing it is refused, and the help names the declaration that would allow it. `qty` in the same function can be written because it was.",
      code: `(import Err)
(import IO)
(import Str)
(import Vec)

(type Quantity UInt16)

(type Cents Int32)

(struct Line
  (sku : String)
  (mut qty : Quantity)
  (unit : Cents))

; An expression macro: it rewrites the call into two additions
; before type checking, so the sum is checked like handwritten code.
(macro sum3 ((sum3 a b c) (+ a (+ b c))))

(:: number (-> String String (Result Int Error)))
(fn (number name text)
  {
    (let bad (mkError 20 (concat text " is not a number")))
    (withContext (okOr (strParseInt text) bad) (concat "reading " name))
  })

; Lines arrive as "sku qty unit-cents". \`?\` binds each number and
; stops at the first one that is not there.
(:: parseLine (-> String (Result Line Error)))
(fn (parseLine text)
  {
    (let parts (strSplit text 32))
    (let qty (number "qty" (vecGet parts 1))?)
    (let unit (number "price" (vecGet parts 2))?)
    (Ok (Line :sku (vecGet parts 0) :qty (as qty Quantity) :unit (as unit Cents)))
  })

; Nothing ships singly: a line for one becomes a line for two.
; \`set\` can write qty because the field is declared \`mut\`.
(:: topUp (-> Line ()))
(fn (topUp line)
  {
    (set line.sku "misc")
    (if (< (as line.qty Int) 2)
      (set line.qty (as 2 Quantity)))
  })

(:: lineTotal (-> Line Cents))
(fn (lineTotal line)
  (* (as line.qty Int32) line.unit))

;@axiom:pre((<= lo hi))
;@axiom:post((&& (>= result lo) (<= result hi)))
(:: clampPct (-> Int Int Int Int))
(fn (clampPct pct lo hi)
  (if (< pct lo)
    lo
    (if (> pct hi)
      hi
      pct)))

; The discount, in the order offers are considered: a coupon if there
; is one, else loyalty points (a percent per ten, capped at 30), else
; 5% over a hundred dollars, else nothing. One \`if\` chain, mixing
; pattern tests with an ordinary Bool test.
(:: discount (-> (Option Int) (Option Int) Cents Int))
(fn (discount coupon loyalty subtotal)
  (if (let (Some pct) coupon)
      pct
    (let (Some points) loyalty)
      (clampPct (/ points 10) 0 30)
    (> subtotal (as 10000 Cents))
      5
    0))

(:: dollars (-> Cents Float))
(fn (dollars cents)
  (/ (as cents Float) 100.0))

(:: checkout (-> String String String (Option Int) (Option Int) (Result String Error)))
(fn (checkout a b c coupon loyalty)
  {
    (let first (parseLine a)?)
    (let second (parseLine b)?)
    (let third (parseLine c)?)
    {
      (topUp first)
      (topUp second)
      (topUp third)
    }
    (let subtotal (sum3 (lineTotal first) (lineTotal second) (lineTotal third)))
    (let pct (discount coupon loyalty subtotal))
    (let off (/ (* subtotal (as pct Cents)) (as 100 Cents)))
    (let due (- subtotal off))
    (let before (dollars subtotal))
    (let after (dollars due))
    (Ok (format "subtotal {before:.2}, discount {pct}%, total {after:.2}"))
  })

(:: report (-> String String String (Option Int) (Option Int) ()))
;@axiom:effect(io)
(fn (report a b c coupon loyalty)
  (match (checkout a b c coupon loyalty)
    ((Ok text) (println text))
    ((Err e) (println (errorText e)))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (report "bolt-m4 3 1250" "nut-m4 4 250" "washer 1 500" None (Some 240))
    (report "bolt-m4 3 1250" "nut-m4 4 250" "washer 1 500" (Some 10) (Some 240))
    (report "bolt-m4 8 1250" "nut-m4 4 250" "washer 1 500" None None)
    (report "bolt-m4 3 1250" "nut-m4 two 250" "washer 1 500" None (Some 240))
  })`,
      human: `error[AX3012]: cannot assign to field \`sku\` of \`Line\`: the field is not declared \`mut\`
  --> orders.ax:42:15
   |
42 |     (set line.sku "misc")
   |               ^^^ \`sku\` is not a \`mut\` field
   |
   = note: a struct field is immutable unless its declaration marks it \`mut\`, the rule \`let\` already follows; until 0.6.0 the marker was parsed and discarded and this store compiled in silence
   = help: declare it mutable where \`Line\` is defined: \`(mut sku : String)\`
   = help: run \`axiom explain AX3012\` for a full explanation

compilation failed due to 1 previous error`,
    },
  },
  {
    id: "links",
    file: "tree.ax",
    tab: "Links & trees",
    title: "A category tree held together by links",
    lede: "Every node lives in one `Vec`, joined by `Link`s: typed indexes that take no share and cost two bytes in a field. Parent links form a cycle that shared references could not free; the vector frees the whole tree at once.",
    points: [
      { at: "(mut parent : (Link Node UInt16))", text: "A `(Link Node UInt16)` names one element of a `(Vec Node)`. Three links cost six bytes per node, where three references would cost twenty-four and three shares to manage." },
      { at: "(let fresh (linkTo nodes (- (vecLen nodes) 1)))", text: "`linkTo` mints the link to the node just pushed. `linkGet` follows one with the same bounds check as `vecGet`; `linkNone` names nothing." },
      { at: "(if (let (Some at) (find nodes name))", text: "The lookup answers `(Option (Link Node UInt16))`, and one `if let` chain handles found, found under its old name, and not stocked." },
      { at: "(region scratch", text: "A link is an index, so the one computed over this scratch copy may leave the region as an `Int` while the copy itself is reclaimed whole." },
    ],
    docs: { label: "Link the elements of a vector", href: `${REF}#link-the-elements-of-a-vector` },
    output: `categories:
shop
  tools
    drills
      cordless
    saws
  garden
    seeds
cordless: shop / tools / drills / cordless
drills (sold as power drills): shop / tools / drills
paint: not stocked
7 categories, last added at index 6`,
    code: `(import IO)
(import Link)
(import Str)
(import Vec)

; A shop's categories. Every node lives in one Vec, and links join
; them: down to the first child, across to the next sibling, and back
; up to the parent. The vector owns each node once, so the cycle the
; parent links form costs nothing to free.
(struct Node
  (name : String)
  (mut parent : (Link Node UInt16))
  (mut child : (Link Node UInt16))
  (mut sibling : (Link Node UInt16)))

(:: attach (-> (Vec Node) (Link Node UInt16) (Link Node UInt16) ()))
(fn (attach nodes at fresh)
  {
    (let n (linkGet nodes at))
    (if (linkIsSome n.sibling)
      (attach nodes n.sibling fresh)
      (set n.sibling fresh))
  })

(:: add (-> (Vec Node) String (Link Node UInt16) (Link Node UInt16)))
(fn (add nodes name parent)
  {
    (vecPush nodes (Node :name name :parent parent :child linkNone :sibling linkNone))
    (let fresh (linkTo nodes (- (vecLen nodes) 1)))
    {
      (if (linkIsSome parent)
        {
          (let p (linkGet nodes parent))
          (if (linkIsSome p.child)
            (attach nodes p.child fresh)
            (set p.child fresh))
        })
      fresh
    }
  })

(:: find (-> (Vec Node) String (Option (Link Node UInt16))))
(fn (find nodes name)
  {
    (let mut hit (:: None (Option (Link Node UInt16))))
    {
      (for i in 0..(vecLen nodes)
        {
          (let n (vecGet nodes i))
          (if (strEq n.name name)
            (set hit (Some (linkTo nodes i))))
        })
      hit
    }
  })

; Root first, by following parent links up and naming each node
; on the way back down.
(:: path (-> (Vec Node) (Link Node UInt16) String))
(fn (path nodes at)
  {
    (let n (linkGet nodes at))
    (if (linkIsSome n.parent)
      (concat (concat (path nodes n.parent) " / ") n.name)
      n.name)
  })

(:: printTree (-> (Vec Node) (Link Node UInt16) String ()))
;@axiom:effect(io)
(fn (printTree nodes at indent)
  (if (linkIsSome at)
    {
      (let n (linkGet nodes at))
      (let label n.name)
      {
        (println "{indent}{label}")
        (printTree nodes n.child (concat indent "  "))
        (printTree nodes n.sibling indent)
      }
    }))

; One chain answers all three: found by its name, found by the name
; it used to be sold under, or not stocked at all.
(:: report (-> (Vec Node) String String ()))
;@axiom:effect(io)
(fn (report nodes name alias)
  (if (let (Some at) (find nodes name))
      {
        (let where (path nodes at))
        (println "{name}: {where}")
      }
    (let (Some at) (find nodes alias))
      {
        (let where (path nodes at))
        (println "{alias} (sold as {name}): {where}")
      }
    (println "{name}: not stocked")))

; A link is an index, not an address, so one computed over a scratch
; copy inside a region still names the right element outside it.
; The copy is reclaimed when the region ends; the index may leave.
(:: lastAdded (-> (Vec Node) Int))
(fn (lastAdded nodes)
  (region scratch
    {
      (let copy (:: vecNew (Vec Node)))
      (for n in nodes
        (vecPush copy n))
      (linkIndex (linkTo copy (- (vecLen copy) 1)))
    }))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let nodes (:: vecNew (Vec Node)))
    (let root (add nodes "shop" linkNone))
    (let tools (add nodes "tools" root))
    (let garden (add nodes "garden" root))
    (let drills (add nodes "drills" tools))
    {
      (add nodes "saws" tools)
      (add nodes "seeds" garden)
      (add nodes "cordless" drills)
      (println "categories:")
      (printTree nodes root "")
      (report nodes "cordless" "cordless")
      (report nodes "power drills" "drills")
      (report nodes "paint" "paint")
      (let total (vecLen nodes))
      (let last (lastAdded nodes))
      (println "{total} categories, last added at index {last}")
    }
  })`,
  },
  {
    id: "digest",
    file: "digest.ax",
    tab: "Pipeline",
    title: "Read TOML, ship on UTC, fingerprint as JSON",
    lede: "Four standard-library modules in one pipeline - `Cereal`, `Chrono` and `Crypto` over `Err` - all of them written in Axiom and calling no C.",
    points: [
      { at: "(let note (cerealDecode CerealToml toml)?)", text: "`Cereal` decodes TOML, JSON and YAML into one typed value. This one is written back out as JSON below." },
      { at: "(let version (cerealField cerealTextCodec note \"version\")?)", text: "A codec reads each field, and a missing or mistyped one is an error that names it - the second note in the output has no version." },
      { at: "(let start (datetimeParseUtc at)?)", text: "`Chrono` applies the +02:00 offset and answers a UTC date-time; adding the parsed duration refuses results outside the supported range." },
      { at: "(let digest (hexEncode (sha256 json)))", text: "`Crypto.Sha2` digests the JSON bytes and `Crypto.Bytes` spells the digest in hex." },
    ],
    docs: { label: "Cereal", href: `${LIB}docs/stdlib.md#cereal` },
    output: `axiom 0.8.0 ships 2024-02-29T23:00:00 UTC
{"name":"axiom","version":"0.8.0","at":"2024-02-29T23:30:00+02:00"}
sha256 f5a23d53a39b761dd4c6ec4e176e3b2e5d10b1d93db63961fa1d4a3c6c112f9d
Cereal: missing field: version while version`,
    code: `(import Cereal)
(import Chrono)
(import Crypto.Bytes)
(import Crypto.Sha2)
(import Err)
(import IO)

; Read a release note written as TOML, say when it ships in UTC,
; and fingerprint the same note written as JSON. Every step that can
; fail returns a Result, and \`?\` hands the first failure back.
(:: announce (-> String (Result String Error)))
(fn (announce toml)
  {
    (let note (cerealDecode CerealToml toml)?)
    (let name (cerealField cerealTextCodec note "name")?)
    (let version (cerealField cerealTextCodec note "version")?)
    (let at (cerealField cerealTextCodec note "at")?)
    (let start (datetimeParseUtc at)?)
    (let delay (durationParse "PT1H30M")?)
    (let when (datetimeAdd start delay)?)
    (let json (cerealEncode CerealJson note)?)
    (let whenText (datetimeToString when))
    (let digest (hexEncode (sha256 json)))
    (Ok (format "{name} {version} ships {whenText} UTC\\n{json}\\nsha256 {digest}"))
  })

(:: report (-> String ()))
;@axiom:effect(io)
(fn (report toml)
  (match (announce toml)
    ((Ok text) (println text))
    ((Err e) (println (errorText e)))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (report "name = \\"axiom\\"\\nversion = \\"0.8.0\\"\\nat = \\"2024-02-29T23:30:00+02:00\\"\\n")
    (report "name = \\"axiom\\"\\nat = \\"2024-02-29T23:30:00+02:00\\"\\n")
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
]
