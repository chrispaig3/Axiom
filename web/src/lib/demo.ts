/**
 * The landing demo's clock.
 *
 * `compile` turns the script in `samples.ts` into a list of timed
 * events, and a frame is what those events leave behind: the editor's
 * buffer and cursor, the shell's scrollback, the marks and the caption.
 * Any moment can be rebuilt by replaying the events before it, so the
 * player can pause, seek to a chapter and loop like a video without the
 * component keeping any history of its own.
 *
 * Nothing here decides WHAT is shown, only when. The text typed, the
 * commands and their output all come from the script the checker
 * replays against the compiler; the marks come from the edits and from
 * the `-->` line of a refusal, never from a hand-written line number.
 */
import type { DemoStep } from '../data/samples.ts'

export type MarkKind = 'edit' | 'error'

export interface Mark {
  /** 1-based. */
  line: number
  kind: MarkKind
  /** For an error: the 0-based column and width of the caret. */
  col?: number
  len?: number
}

export interface ShellBlock {
  kind: 'cmd' | 'out' | 'err'
  text: string
}

export interface Frame {
  code: string
  /** Offset into `code`. */
  cursor: number
  focus: 'editor' | 'shell'
  /** First editor line in view, 0-based. */
  top: number
  marks: Mark[]
  shell: ShellBlock[]
  /** The command being typed at the prompt. */
  input: string
  /** A command is running: the prompt is withheld. */
  busy: boolean
  chapter: number
  caption: string
}

export interface Chapter {
  name: string
  start: number
}

export interface Timeline {
  events: { t: number; apply: (f: Frame) => void }[]
  chapters: Chapter[]
  /** When the last event fires. */
  end: number
}

/** Lines the editor pane shows; the view scrolls to keep the cursor in it. */
export const VISIBLE_LINES = 22

export function emptyFrame(): Frame {
  return {
    code: '',
    cursor: 0,
    focus: 'editor',
    top: 0,
    marks: [],
    shell: [],
    input: '',
    busy: false,
    chapter: 0,
    caption: '',
  }
}

export function cloneFrame(f: Frame): Frame {
  return { ...f, marks: f.marks.map((m) => ({ ...m })), shell: f.shell.map((b) => ({ ...b })) }
}

const lineOf = (code: string, offset: number) => code.slice(0, offset).split('\n').length

/** Keep line `line` (1-based) inside the view, with a little margin. */
function reveal(f: Frame, line: number) {
  const total = f.code.split('\n').length
  const margin = 3
  if (line - 1 < f.top + 1) f.top = Math.max(0, line - 1 - margin)
  else if (line > f.top + VISIBLE_LINES - margin) f.top = line - VISIBLE_LINES + margin
  f.top = Math.max(0, Math.min(f.top, Math.max(0, total - VISIBLE_LINES)))
}

/**
 * A small deterministic jitter in [0, 1), so typing has a human rhythm
 * and yet every playthrough is the same. Integer mixing rather than
 * `Math.sin`, whose last bits differ between engines: the server's
 * render and the browser's must agree on every chapter's start time.
 */
function jitter(seed: number): number {
  let x = Math.imul(seed, 0x9e3779b1) >>> 0
  x = Math.imul(x ^ (x >>> 16), 0x45d9f3b) >>> 0
  x = (x ^ (x >>> 16)) >>> 0
  return x / 4294967296
}

/** Parse a human report for the first `--> file:L:C` and its caret. */
export function errorAt(report: string): { line: number; col: number; len: number } | null {
  const loc = /-->\s+\S+?:(\d+):(\d+)/.exec(report)
  if (!loc) return null
  const caret = /^\s*\|\s*?( *)(\^+)/m.exec(report.slice(loc.index))
  return {
    line: Number(loc[1]),
    col: Number(loc[2]) - 1,
    len: caret?.[2]?.length ?? 1,
  }
}

export function compile(steps: DemoStep[]): Timeline {
  const events: Timeline['events'] = []
  const chapters: Chapter[] = []
  let t = 0
  let n = 0
  const at = (apply: (f: Frame) => void) => events.push({ t, apply })

  // Whether typing is an edit to an existing program (marked) or the
  // program being written from nothing (not marked: it would all be).
  let editing = false
  // A step `after` moves the cursor; the typing that follows is an edit.
  let pendingEdit = false

  for (const step of steps) {
    switch (step.do) {
      case 'chapter': {
        const index = chapters.length
        t += index === 0 ? 0 : 500
        chapters.push({ name: step.name, start: t })
        at((f) => {
          f.chapter = index
          f.marks = []
          f.focus = 'editor'
        })
        t += 250
        break
      }

      case 'say': {
        const text = step.text
        at((f) => {
          f.caption = text
        })
        break
      }

      case 'after': {
        const needle = step.text
        t += 350
        at((f) => {
          const i = f.code.indexOf(needle)
          if (i < 0) return
          f.focus = 'editor'
          f.cursor = i + needle.length
          reveal(f, lineOf(f.code, f.cursor))
        })
        t += 450
        pendingEdit = true
        break
      }

      case 'type': {
        editing = pendingEdit
        pendingEdit = false
        // The first program is written quickly; an edit is typed at a
        // pace a reader can follow.
        const pace = editing ? 34 : 14
        const text = step.text
        let atLineStart = false
        for (let i = 0; i < text.length; i++) {
          const ch = text[i] as string
          const mark = editing
          at((f) => {
            f.focus = 'editor'
            f.code = f.code.slice(0, f.cursor) + ch + f.code.slice(f.cursor)
            f.cursor += 1
            const line = lineOf(f.code, f.cursor)
            if (ch === '\n') {
              // A new line pushes every mark below it down one.
              for (const m of f.marks) if (m.line >= line) m.line += 1
            }
            if (mark && ch !== '\n' && !f.marks.some((m) => m.line === line && m.kind === 'edit')) {
              f.marks.push({ line, kind: 'edit' })
            }
            reveal(f, line)
          })
          // Indentation after a newline arrives at once, as an editor
          // would put it there; everything else is keystrokes.
          if (ch === '\n') {
            atLineStart = true
            t += editing ? 160 : 45
          } else if (atLineStart && ch === ' ') {
            t += 0
          } else {
            atLineStart = false
            t += Math.round(pace * (0.55 + 0.9 * jitter(++n)) + (ch === ' ' ? pace * 0.4 : 0))
          }
        }
        t += editing ? 500 : 250
        break
      }

      case 'run': {
        const { command, output } = step
        const failed = step.exit === 1
        t += 300
        at((f) => {
          f.focus = 'shell'
        })
        t += 200
        for (let i = 1; i <= command.length; i++) {
          const typed = command.slice(0, i)
          at((f) => {
            f.input = typed
          })
          t += Math.round(30 * (0.6 + 0.8 * jitter(++n)))
        }
        t += 260
        at((f) => {
          f.shell.push({ kind: 'cmd', text: command })
          f.input = ''
          f.busy = true
        })
        // The command's own work: a compile takes a moment, running a
        // built binary does not. Not a measurement; the benchmark is.
        t += command.startsWith('./') ? 160 : 650
        const lines = output.split('\n')
        at((f) => {
          f.shell.push({ kind: failed ? 'err' : 'out', text: '' })
        })
        lines.forEach((_, i) => {
          const text = lines.slice(0, i + 1).join('\n')
          at((f) => {
            const last = f.shell[f.shell.length - 1]
            if (last) last.text = text
          })
          t += failed ? 38 : 70
        })
        const where = failed ? errorAt(output) : null
        at((f) => {
          f.busy = false
          if (where) {
            f.marks.push({ line: where.line, kind: 'error', col: where.col, len: where.len })
            reveal(f, where.line)
          }
        })
        t += 900
        break
      }

      case 'wait':
        t += step.ms
        break
    }
  }

  return { events, chapters, end: t }
}

/** The frame at `ms`, replayed from nothing. */
export function frameAt(tl: Timeline, ms: number): Frame {
  const f = emptyFrame()
  for (const e of tl.events) {
    if (e.t > ms) break
    e.apply(f)
  }
  return f
}
