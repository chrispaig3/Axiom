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
 *   - the Rust excerpt is a verbatim slice of the crate it names.
 *
 *   ./scripts/bootstrap-from-seed.sh --install .axiom-bin
 *   cd web && npm run check:samples
 *
 * Run it after changing a sample, the compiler, or the standard
 * library. A sample that drifts fails there, not on the page.
 *
 * The programs are small real tasks rather than feature demos in
 * costume: a reader can tell the difference, and it is the fastest way
 * to lose one.
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

export interface Program {
  id: string
  /** The file name it runs as, and the label on its frame. */
  file: string
  /** Short label for a tab or a chapter list. */
  tab: string
  title: string
  /** What it shows, in a sentence or two. Backticks become <code>. */
  lede: string
  /** What to notice, one line each. */
  points: string[]
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

/** A mutation of the hero program, and the compiler's answer to it. */
export interface Breakage {
  id: string
  label: string
  title: string
  note: string
  code: string
  /** 1-based lines of `code` that differ from the hero program. */
  changed: number[]
  human: string
  ai: string
}

const LIB = 'https://github.com/chrispaig3/Axiom/blob/trunk/'
const REF = `${LIB}docs/reference.md`

/** The shell command that produced a program's output. */
export function commandFor(p: Program): string {
  const verb = p.mode ?? 'run'
  return `axiom ${verb} ${p.file}${p.crate ? ` --crate ${p.crate}` : ''}`
}

/**
 * The hero: one screen of Axiom that shows the shape of the language -
 * a sum type with named fields, an exhaustive match, a function that
 * promises no I/O, and one that declares it does.
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
 * The hero's terminal: five commands against the hero program, each
 * a tab. `steps` are what `check-samples.mjs` runs, in order, in the
 * program's directory (`./name` runs what a step built); `grep` and
 * `head` are applied the way the pipe the prompt shows applies them.
 * `output` is the result, compared byte for byte.
 */
export interface Session {
  id: string
  tab: string
  /** The command line the prompt shows. */
  command: string
  steps: string[][]
  grep?: string
  head?: number
  output: string
  /** One line on why a reader should care. */
  note: string
}

export const HERO_SESSIONS: Session[] = [
  {
    id: 'run',
    tab: 'run',
    command: 'axiom run shapes.ax',
    steps: [['run', 'shapes.ax']],
    output: `circle       12.57
rect         13.50
triangle      6.00`,
    note: 'Compile and run in one step. No build file, no project needed.',
  },
  {
    id: 'check',
    tab: 'check',
    command: 'axiom check shapes.ax',
    steps: [['check', 'shapes.ax']],
    output: 'OK',
    note: 'Types, exhaustiveness and every effect claim, verified without generating code.',
  },
  {
    id: 'symbols',
    tab: 'symbols',
    command: 'axiom --diagnostic-format=ai symbols shapes.ax | grep shapes.ax',
    steps: [['--diagnostic-format=ai', 'symbols', 'shapes.ax']],
    grep: ' shapes.ax:',
    output: `F area shapes.ax:8:5-9 "(Shape -> Float)" @925bb7869087e3f6 #restrict=no-io
F report shapes.ax:16:5-11 "(String -> (Shape -> Int))" @c9dfa4d37f242eb5 #effect=io #effects=Alloc,IO,Mut,Unsafe
F main shapes.ax:22:5-9 "Int" @6159d363201f7f2a #effect=io #effects=Alloc,IO,Mut,Unsafe
D Shape shapes.ax:3:7-12 "data Shape" @f67d31a9f1847a1c #ctors=Circle,Rect,Triangle
C Circle shapes.ax:4:4-10 "(Float -> Shape)" #of=Shape
C Rect shapes.ax:5:4-8 "(Float -> (Float -> Shape))" #of=Shape
C Triangle shapes.ax:6:4-12 "(Float -> (Float -> Shape))" #of=Shape`,
    note: 'One line per declaration: exact type, a stable id, the claim it makes and the effects it performs. What an agent reads instead of the file.',
  },
  {
    id: 'build',
    tab: 'build',
    command: 'axiom build shapes.ax -o shapes && ./shapes',
    steps: [['build', 'shapes.ax', '-o', 'shapes'], ['./shapes']],
    output: `Build successful: shapes
circle       12.57
rect         13.50
triangle      6.00`,
    note: 'A native executable. Its allocator and its syscalls are inside it.',
  },
  {
    id: 'explain',
    tab: 'explain',
    command: 'axiom explain AX3049 | head -7',
    steps: [['explain', 'AX3049']],
    head: 7,
    output: `AX3049 - a restriction this declaration claimed, violated

\`;@axiom:restrict(no-io)\` is a claim that this function and everything
it reaches performs no IO. This is the compiler answering it, with the
path:

    parseConfig -> readSection -> IO$writeStr -> ... -> __syscall3`,
    note: 'Every diagnostic code has a written explanation, in the binary you already have.',
  },
]

/**
 * What a reader should notice in the hero program, pinned to its lines.
 * Hovering or focusing a note marks its line in the code. `token` is
 * text that line must contain: `check-samples.mjs` holds every note to
 * its line, so an edit that shifts the program cannot leave a note
 * pointing at the wrong one.
 */
export const HERO_NOTES = [
  { line: 3, token: '(data Shape', title: 'A sum type', body: 'Three shapes, each with named fields.' },
  {
    line: 9,
    token: ';@axiom:restrict(no-io)',
    title: 'A checked promise',
    body: '`area` may not perform I/O, and the compiler holds it to that through every call it makes.',
  },
  {
    line: 11,
    token: '(match s',
    title: 'Exhaustive matching',
    body: 'Every shape is handled, or the program does not compile.',
  },
  {
    line: 17,
    token: ';@axiom:effect(io)',
    title: 'Declared I/O',
    body: '`report` prints, and says so. Delete the tag and the build stops.',
  },
  {
    line: 20,
    token: '{a:>8.2}',
    title: 'Formatting at compile time',
    body: '`{a:>8.2}` picks its functions while compiling; no format string survives to run time.',
  },
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

/** The file every breakage is checked as, so its diagnostics name it. */
export const BREAK_FILE = 'shapes.ax'

/**
 * "Try to break it": five one-line edits to the hero program, each
 * refused. Ordered from the check every typed language has to the ones
 * only this compiler makes.
 */
export const BREAKS: Breakage[] = [
  {
    id: "variant",
    label: "Add a shape",
    title: "Add a case, and every match that missed it is named",
    note: "A `Hexagon` joins the type. `area` no longer covers every shape, so the build stops at the `match`, and the missing arm arrives as a machine-applicable fix.",
    changed: [6, 7],
    code: `(import IO)

(data Shape
  (Circle { r : Float })
  (Rect { w : Float, h : Float })
  (Triangle { b : Float, h : Float })
  (Hexagon { side : Float }))

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
    human: `error[AX3005]: non-exhaustive pattern match: missing Hexagon
  --> shapes.ax:12:10
   |
12 |   (match s
   |          ^ this \`match\` does not cover: Hexagon
   |
   = help: add the missing arms, each a \`todo\` until it is written ~>
               ((Hexagon _) (todo "Hexagon"))
   = help: run \`axiom explain AX3005\` for a full explanation

compilation failed due to 1 previous error`,
    ai: `E AX3005 shapes.ax:12:10-11 non-exhaustive-match "non-exhaustive pattern match: missing Hexagon" #"this \`match\` does not cover: Hexagon" ?15:48:"add the missing arms, each a \`todo\` until it is written"~>"\\n    ((Hexagon _) (todo \\"Hexagon\\"))"
compilation failed due to 1 previous error`,
  },
  {
    id: "log",
    label: "Log from a pure function",
    title: "A debug print breaks a promise, and the path is traced",
    note: "`area` promised `restrict(no-io)`. One `println` later, the compiler shows the chain of calls from `area` down to the syscall, file and line for each hop.",
    changed: [12, 13, 14, 15, 16, 17],
    code: `(import IO)

(data Shape
  (Circle { r : Float })
  (Rect { w : Float, h : Float })
  (Triangle { b : Float, h : Float }))

(:: area (-> Shape Float))
;@axiom:restrict(no-io)
(fn (area s)
  (match s
    ((Circle {r = r})
      {
        (println "debug: r = {r}")
        (* 3.14159 (* r r))
      }
    )
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
    human: `error[AX3049]: \`area\` claims \`restrict(no-io)\` and the body performs IO: area -> IO$writeStr -> Sys$sysWriteAllFd -> Sys$sysWriteFd -> __syscall3
  --> shapes.ax:10:6
   |
10 | (fn (area s)
   |      ^^^^
   |
   = note: IO$writeStr (stdlib/IO.ax:42:10-18)
   = note: Sys$sysWriteAllFd (stdlib/Sys.ax:210:10-23)
   = note: Sys$sysWriteFd (stdlib/Sys.ax:166:10-20)
   = note: __syscall3 (no declaration to point at)
   = help: a restriction is a CLAIM the author wrote, and this is the compiler answering it. \`no-io\`, \`no-alloc\`, \`no-unsafe\`, \`no-foreign\`, \`no-cast:deep\` and \`no-recursion\` are transitive - the effect row and the call graph are fixpoints over every callee - and the path in the message is the chain of resolved calls (\`symbols --calls\` spells each hop the same way) from this declaration to where the effect enters, or around the cycle, so the fix is at a named place rather than somewhere below. Make the body keep the claim, or delete the tag, which WITHDRAWS the claim rather than answering it; an unrestricted function is never asked
   = help: run \`axiom explain AX3049\` for a full explanation

error[AX3042]: \`area\` performs IO and its declaration does not say so
  --> shapes.ax:10:6
   |
10 | (fn (area s)
   |      ^^^^
   |
   = help: write \`;@axiom:effect(io)\` above the declaration ~>
           ;@axiom:effect(io)
   = help: effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so; \`Alloc\` and \`Mut\` are ambient and never need declaring
   = help: run \`axiom explain AX3042\` for a full explanation

compilation failed due to 2 previous errors`,
    ai: `E AX3049 shapes.ax:10:6-10 restriction-violated "\`area\` claims \`restrict(no-io)\` and the body performs IO: area -> IO$writeStr -> Sys$sysWriteAllFd -> Sys$sysWriteFd -> __syscall3" ^stdlib/IO.ax:42:10-18:"IO$writeStr" ^stdlib/Sys.ax:210:10-23:"Sys$sysWriteAllFd" ^stdlib/Sys.ax:166:10-20:"Sys$sysWriteFd" ^-:"__syscall3" ?"a restriction is a CLAIM the author wrote, and this is the compiler answering it. \`no-io\`, \`no-alloc\`, \`no-unsafe\`, \`no-foreign\`, \`no-cast:deep\` and \`no-recursion\` are transitive - the effect row and the call graph are fixpoints over every callee - and the path in the message is the chain of resolved calls (\`symbols --calls\` spells each hop the same way) from this declaration to where the effect enters, or around the cycle, so the fix is at a named place rather than somewhere below. Make the body keep the claim, or delete the tag, which WITHDRAWS the claim rather than answering it; an unrestricted function is never asked"
E AX3042 shapes.ax:10:6-10 undeclared-effect "\`area\` performs IO and its declaration does not say so" ?10:1:"write \`;@axiom:effect(io)\` above the declaration"~>";@axiom:effect(io)\\n" ?"effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so; \`Alloc\` and \`Mut\` are ambient and never need declaring"
compilation failed due to 2 previous errors`,
  },
  {
    id: "undeclared",
    label: "Drop an effect tag",
    title: "Silence is a claim too",
    note: "Without `;@axiom:effect(io)`, `report` claims it performs no I/O. The compiler infers that it does, transitively, and says so, with the missing line as the fix.",
    changed: [17],
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
    human: `error[AX3042]: \`report\` performs IO and its declaration does not say so
  --> shapes.ax:17:6
   |
17 | (fn (report name s)
   |      ^^^^^^
   |
   = help: write \`;@axiom:effect(io)\` above the declaration ~>
           ;@axiom:effect(io)
   = help: effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so; \`Alloc\` and \`Mut\` are ambient and never need declaring
   = help: run \`axiom explain AX3042\` for a full explanation

compilation failed due to 1 previous error`,
    ai: `E AX3042 shapes.ax:17:6-12 undeclared-effect "\`report\` performs IO and its declaration does not say so" ?17:1:"write \`;@axiom:effect(io)\` above the declaration"~>";@axiom:effect(io)\\n" ?"effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so; \`Alloc\` and \`Mut\` are ambient and never need declaring"
compilation failed due to 1 previous error`,
  },
  {
    id: "typo",
    label: "Misspell a name",
    title: "A typo, with the fix attached",
    note: "The replacement travels with the error as a span and a string, so an editor or an agent applies it without reading the prose.",
    changed: [19],
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
  (let ((a (aera s)))
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
    human: `error[AX3001]: undefined variable \`aera\`
  --> shapes.ax:19:13
   |
19 |   (let ((a (aera s)))
   |             ^^^^ no binding named \`aera\` in scope
   |
   = help: a similarly named binding \`area\` is in scope; did you mean this? ~> area
   = help: run \`axiom explain AX3001\` for a full explanation

compilation failed due to 1 previous error`,
    ai: `E AX3001 shapes.ax:19:13-17 undefined-variable "undefined variable \`aera\`" #"no binding named \`aera\` in scope" ?19:13-17:"a similarly named binding \`area\` is in scope; did you mean this?"~>"area"
compilation failed due to 1 previous error`,
  },
  {
    id: "type",
    label: "Pass an Int",
    title: "No silent conversions",
    note: "`3` is an `Int` and `Rect` wants a `Float`. Nothing is coerced, and the caret lands on the exact argument.",
    changed: [27],
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
    (report "rect" (Rect 3 4.5))
    (report "triangle" (Triangle 4.0 3.0))
    0
  })`,
    human: `error[AX3004]: type mismatch: expected Float, found Int
  --> shapes.ax:27:26
   |
27 |     (report "rect" (Rect 3 4.5))
   |                          ^ this has type \`Int\`, expected \`Float\`
   |
   = help: run \`axiom explain AX3004\` for a full explanation

compilation failed due to 1 previous error`,
    ai: `E AX3004 shapes.ax:27:26-27 type-mismatch "type mismatch: expected Float, found Int" #"this has type \`Int\`, expected \`Float\`"
compilation failed due to 1 previous error`,
  },
]

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
    lede: "Sum types with named fields, matched exhaustively. Every constructor is handled or the program does not compile, and `Option` is built in, so \"no value\" is a type rather than a null.",
    points: [
      "`(data Parcel …)` declares four states; two of them carry named fields.",
      "`match` must cover every constructor, in every function that looks.",
      "`{id:<9}` pads inside the string. The format is decided at compile time.",
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
    refusal: {
      label: "Add a fifth state",
      note: "Add `(Returned)` to the type. Both functions that match on a `Parcel` stop compiling, and each error carries the missing arm as a fix a tool can apply.",
      code: `(import IO)
(import Err)

(data Parcel
  (Ordered)
  (InTransit { carrier : String, days : Int })
  (Held { why : String })
  (Delivered)
  (Returned))

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
      human: `error[AX3005]: non-exhaustive pattern match: missing Returned
  --> parcels.ax:13:10
   |
13 |   (match p
   |          ^ this \`match\` does not cover: Returned
   |
   = help: add the missing arms, each a \`todo\` until it is written ~>
               ((Returned) (todo "Returned"))
   = help: run \`axiom explain AX3005\` for a full explanation

error[AX3005]: non-exhaustive pattern match: missing Returned
  --> parcels.ax:21:10
   |
21 |   (match p
   |          ^ this \`match\` does not cover: Returned
   |
   = help: add the missing arms, each a \`todo\` until it is written ~>
               ((Returned) (todo "Returned"))
   = help: run \`axiom explain AX3005\` for a full explanation

compilation failed due to 2 previous errors`,
    },
  },
  {
    id: "records",
    file: "stock.ax",
    tab: "Records",
    title: "Restock the shelf",
    lede: "Structs are built positionally and read by name. A field is immutable unless its declaration says `mut`, and any record prints without a line of formatting code.",
    points: [
      "`(mut qty : Int)`: mutability is declared per field, not per variable.",
      "`(for item shelf …)` walks a `Vec` of structs.",
      "`{item}` renders the whole record, strings quoted.",
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
    lede: "Failure is a value. `Result` carries it, `try!` short-circuits on it, and `withContext` records where it happened. Overflow can be an error too: `mulChecked` refuses where `*` would wrap.",
    points: [
      "`okOr` turns an `Option` into a `Result` with a real error.",
      "`try!` binds the success and returns the first failure unchanged.",
      "The error text says which step failed, not only that one did.",
    ],
    docs: { label: "The error model", href: `${LIB}docs/error-model.md` },
    output: `4096 x 256 = 1048576 bytes`,
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
    ((Err e) (eprintln (errorText e)))))

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
    lede: "Declare an effect, perform it anywhere, and decide what it means where you call it. The same `retry` prints its plan in the program and hands a test its pauses as data. No mocking framework.",
    points: [
      "`(effect Pause …)` declares an operation; calling `pause` performs it.",
      "`;@axiom:effect(pause)` is a claim the compiler checks against the body.",
      "`handle` installs a handler for everything the body calls, at any depth.",
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
    lede: "`Vec`, `Map` and a string interner, from a standard library written in Axiom. None of it calls C: printing, allocation and sorting all compile into your binary.",
    points: [
      "`for msg inbox` walks a `Vec String` element by element.",
      "Words are interned to ids, counted in a `Map`, and ranked with `vecSortBy`.",
      "The comparator is a lambda that closes over the map.",
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
            (let ((w (bare (vecGetStr parts i))))
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
    lede: "`parallel` runs each binding beside the caller and joins them in the order written. Child processes by default, threads under `--threads`: the same program, the same bytes out.",
    points: [
      "Three shards are scanned at once; the body sees all three counts.",
      "Joins happen in written order, so which shard finished first is not observable.",
      "Only a machine word crosses a join, and that rule is checked.",
    ],
    docs: { label: "parallel", href: `${REF}#parallel--bindings-that-run-beside-the-caller` },
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
    lede: "`(region r body)` rolls the allocator back when `body` ends, so everything a request built is reclaimed in one step. Only scalars may leave a region, and the compiler checks that.",
    points: [
      "Each iteration renders a fresh `String` inside its own region.",
      "The `Int` total is written through; the strings are not kept.",
      "A region is a stack slot, so a million of them leave the heap where it was.",
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
    lede: "Macros rewrite the program tree before type checking, so everything they generate is checked like code you wrote. They can declare functions, repeat over any number of arguments, and read a type's constructors.",
    points: [
      "`defUnit` writes a signature and a function per line.",
      "`total` matches one argument or many, recursively.",
      "`(deriveEq Plan)` writes `eqPlan` from the constructor list. No user code runs at compile time.",
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
    lede: "A test is a function whose name starts with `test`. `axiom test` finds them without registration, runs each in its own recovery point, and a failed assertion ends only that test.",
    points: [
      "No attributes, no manifest: the name is the registration.",
      "Every assertion takes a label first, so a failure says what it meant.",
      "A file with no tests fails rather than passing empty.",
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
(:: part (-> (Vec Int) Int Int))
(fn (part parts i)
  (if (< i (vecLen parts))
    (optUnwrapOr (strParseInt (vecGetStr parts i)) 0)
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
    lede: "Mark Rust functions `#[axiom_export]` and `axiom-bindgen` writes the Axiom module for them. `--crate` builds the archive and links it. Strings, `Result`s and owned handles cross the boundary; the Rust value is dropped when the last Axiom reference goes.",
    points: [
      "`shout` takes a borrowed string and returns an owned one.",
      "`Counter` is an opaque Rust type held as a counted handle.",
      "`parseInt` returns a Rust `Result`, matched like any Axiom one.",
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

/* ------------------------------------------------------------------ *
 * The agent-facing notation. Every block below is quoted exactly, from
 * the file named beside it.
 * ------------------------------------------------------------------ */

/** docs/diagnostics.md — a typo on line 6, and the fix that travels with it. */
export const FIX_SOURCE = `(:: helper (-> Int Int))
(fn (helper x) (+ x 1))

(:: main Int)
(fn (main)
  (helpr 5))`

/** docs/diagnostics.md — the same line the compiler prints today; its byte count is computed where it is quoted. */
export const FIX_AXDL =
  'E AX3001 main.ax:6:4-9 undefined-variable "undefined variable `helpr`" #"no binding named `helpr` in scope" ?6:4-9:"a similarly named binding `helper` is in scope; did you mean this?"~>"helper"'

/** docs/diagnostics.md — the same diagnostic as JSON Lines. */
export const FIX_JSON =
  '{"severity":"error","code":"AX3001","slug":"undefined-variable","message":"undefined variable `helpr`","file":"main.ax","span":{"start":{"line":6,"col":4},"end":{"line":6,"col":9},"char_start":78,"char_end":83},"label":"no binding named `helpr` in scope","related":[],"notes":[],"help":["a similarly named binding `helper` is in scope; did you mean this?"],"expansion":[]}'

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
Data     Vec                  data Vec                                 [builtin]
Data     Maybe                data Maybe                               [main.ax:1:7-12]
Ctor     Nothing              Maybe a                                  [main.ax:2:4-11]
Ctor     Just                 (a -> Maybe a)                           [main.ax:3:4-8]
Struct   Point                struct Point                             [main.ax:5:9-14]`

/** docs/diagnostics.md — the same file under --diagnostic-format=ai. */
export const AXSYM_AI = `F add main.ax:9:5-8 "(Int -> (Int -> Int))" @27bcb2cac184465e
D Option - "data Option" #ctors=Some,None
C Some - "(a -> Option a)" #of=Option
C None - "Option a" #of=Option
D Vec - "data Vec"
D Maybe main.ax:1:7-12 "data Maybe" @247d1682b2330461 #ctors=Nothing,Just
C Nothing main.ax:2:4-11 "Maybe a" #of=Maybe
C Just main.ax:3:4-8 "(a -> Maybe a)" #of=Maybe
S Point main.ax:5:9-14 "struct Point" @aa47cd1e9254cc56 #fields=x:Int,y:Int`
