import {
  Fragment,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { highlight, type Token } from '../lib/highlight.ts'
import { highlightRust } from '../lib/highlight-rust.ts'
import { Check, Copy } from './Icons.tsx'

export type Lang = 'axiom' | 'rust' | 'plain'

const cls = (capture: Token['capture']) => `tok-${capture.replace(/\./g, '-')}`

function tokensFor(code: string, lang: Lang): Token[] {
  if (lang === 'axiom') return highlight(code)
  if (lang === 'rust') return highlightRust(code)
  return [{ text: code, capture: 'text' }]
}

/**
 * Split the token stream into lines.
 *
 * The number is rendered INSIDE the line it numbers, not in a sibling
 * gutter column: a sibling has its own line box, which is how numbers
 * once came to sit beside the wrong lines on a narrow screen. One line
 * box holding both halves cannot drift.
 */
export function toLines(tokens: Token[]): Token[][] {
  const lines: Token[][] = [[]]
  for (const t of tokens) {
    const parts = t.text.split('\n')
    parts.forEach((part, i) => {
      if (i > 0) lines.push([])
      if (part) (lines[lines.length - 1] as Token[]).push({ ...t, text: part })
    })
  }
  return lines
}

export function paint(line: Token[]) {
  return line.map((t, j) =>
    t.capture === 'text' ? (
      <Fragment key={j}>{t.text}</Fragment>
    ) : (
      <span key={j} className={cls(t.capture)}>
        {t.text}
      </span>
    ),
  )
}

/**
 * How a line is lit, and why: `focus` is the line a sentence beside the
 * code is about, `edit` a line a reader's change touched, `error` the
 * line a refusal points at. Each has its own colour, so a highlight
 * always says which of the three it is.
 */
export type LineMark = 'focus' | 'edit' | 'error'

/** Highlighted code, one block per line, each carrying its number. */
export function Lines({
  code,
  lang = 'axiom',
  marks,
  numbered = true,
}: {
  code: string
  lang?: Lang
  /** 1-based line number to how it is lit. */
  marks?: ReadonlyMap<number, LineMark> | undefined
  numbered?: boolean
}) {
  const lines = useMemo(() => toLines(tokensFor(code, lang)), [code, lang])
  const width = `${String(lines.length).length}ch`
  return (
    <code style={{ ['--ln-w' as string]: width }}>
      {lines.map((line, i) => (
        <span
          className="ln"
          data-mark={marks?.get(i + 1)}
          key={i}
          data-numbered={numbered || undefined}
        >
          {numbered && (
            <span className="ln__n" aria-hidden>
              {i + 1}
            </span>
          )}
          {paint(line)}
          {'\n'}
        </span>
      ))}
    </code>
  )
}

/** A button that copies `text`, and says so. */
export function CopyButton({ text, label = 'Copy' }: { text: string; label?: string }) {
  const [copied, setCopied] = useState(false)
  const timer = useRef<number | undefined>(undefined)
  useEffect(() => () => window.clearTimeout(timer.current), [])

  const copy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(true)
      window.clearTimeout(timer.current)
      timer.current = window.setTimeout(() => setCopied(false), 1600)
    } catch {
      // Clipboard access can be denied; the text is selectable either way.
    }
  }, [text])

  return (
    <button
      type="button"
      className="copy-btn"
      onClick={copy}
      data-copied={copied}
      aria-label={copied ? 'Copied' : `${label} to clipboard`}
    >
      {copied ? <Check size={13} /> : <Copy size={13} />}
      <span aria-hidden>{copied ? 'Copied' : label}</span>
    </button>
  )
}

interface WindowProps {
  /** File name in the title bar. */
  name: string
  code: string
  lang?: Lang
  badge?: ReactNode
  marks?: ReadonlyMap<number, LineMark> | undefined
  numbered?: boolean
  /** Lines past which the body opens folded. */
  foldAt?: number
  /** Replaces the copy button's text, e.g. to copy the unbroken program. */
  copyText?: string | null
  children?: ReactNode
  className?: string
  label?: string
}

/**
 * A code window: title bar with the file name, a copy button, the
 * numbered source, and whatever the caller docks under it (a run
 * strip, a caption).
 *
 * Long programs open folded. The fold is a `max-height`, so the whole
 * program stays in the DOM for a reader who searches or copies, and
 * for a crawler, which never clicks.
 */
export function CodeWindow({
  name,
  code,
  lang = 'axiom',
  badge,
  marks,
  numbered = true,
  foldAt,
  copyText,
  children,
  className,
  label,
}: WindowProps) {
  const [open, setOpen] = useState(false)
  const count = useMemo(() => code.split('\n').length, [code])
  const foldable = foldAt !== undefined && count > foldAt
  const folded = foldable && !open

  // A new program resets the fold.
  useEffect(() => setOpen(false), [code])

  // A lit line is never left under the fold: the folded body shows about
  // two dozen lines, so a mark past them opens the program.
  useEffect(() => {
    if (foldable && marks && [...marks.keys()].some((l) => l > 22)) setOpen(true)
  }, [marks, foldable])

  return (
    <figure className={['win ink', className].filter(Boolean).join(' ')} aria-label={label}>
      <div className="win__bar">
        <span className="win__dots" aria-hidden>
          <i />
          <i />
          <i />
        </span>
        <span className="win__name">{name}</span>
        {badge && (
          <span className="win__badge">
            {typeof badge === 'string' ? <span className="badge">{badge}</span> : badge}
          </span>
        )}
        {copyText !== null && <CopyButton text={copyText ?? code} />}
      </div>
      <div className={folded ? 'win__body win__body--folded' : 'win__body'}>
        <pre tabIndex={0}>
          <Lines code={code} lang={lang} marks={marks} numbered={numbered} />
        </pre>
      </div>
      {foldable && (
        <div className="win__fold">
          <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={!folded}>
            {folded ? `Show all ${count} lines` : 'Fold the program'}
          </button>
        </div>
      )}
      {children}
    </figure>
  )
}

/** A plain code block, for snippets that are not whole files. */
export function Snippet({ code, lang = 'plain' }: { code: string; lang?: Lang }) {
  return (
    <pre className="snippet ink" tabIndex={0}>
      <Lines code={code} lang={lang} numbered={false} />
    </pre>
  )
}

const reducedMotion = () =>
  typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches

type Phase = 'static' | 'waiting' | 'busy' | 'reveal'

/**
 * The run strip: `$ axiom run f.ax`, then the program's real output.
 *
 * THE OUTPUT IS IN THE SERVER-RENDERED PAGE. The strip used to start in
 * a "compiling…" state and render the lines only after an effect ran,
 * so the prerendered HTML every crawler reads said "compiling…" where
 * the output belonged. Now the first render is the finished state, on
 * the server and the client alike, and the animation is an
 * enhancement: it plays when the strip first scrolls into view (if it
 * was off-screen at load) and whenever `replay` changes, never under
 * `prefers-reduced-motion`.
 *
 * The compile beat is theatre and is labelled as such nowhere because
 * it claims nothing: it is not a measured time, and the benchmark
 * section carries the numbers that are.
 */
export function RunOutput({
  command,
  output,
  replay,
  tone = 'ok',
}: {
  command: string
  output: string
  /** Changing this replays the animation (a tab switch). */
  replay?: string
  /** `err` paints the output as compiler errors rather than stdout. */
  tone?: 'ok' | 'err'
}) {
  const lines = useMemo(() => output.split('\n'), [output])
  const [phase, setPhase] = useState<Phase>('static')
  const [shown, setShown] = useState(lines.length)
  const ref = useRef<HTMLDivElement>(null)
  const timers = useRef<number[]>([])
  const first = useRef(true)

  const clear = () => {
    for (const t of timers.current) window.clearTimeout(t)
    timers.current = []
  }

  const play = useCallback(() => {
    clear()
    setShown(0)
    setPhase('busy')
    const step = Math.max(40, Math.min(120, 900 / lines.length))
    timers.current.push(
      window.setTimeout(() => setPhase('reveal'), 380),
      ...lines.map((_, i) => window.setTimeout(() => setShown(i + 1), 420 + i * step)),
    )
  }, [lines])

  // First mount: animate on first sight, if the strip starts off-screen.
  useEffect(() => {
    if (!first.current) return
    first.current = false
    const el = ref.current
    if (!el || reducedMotion() || typeof IntersectionObserver !== 'function') return
    if (el.getBoundingClientRect().top < window.innerHeight) return
    setPhase('waiting')
    setShown(0)
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          io.disconnect()
          play()
        }
      },
      { rootMargin: '0px 0px -12% 0px' },
    )
    io.observe(el)
    return () => {
      io.disconnect()
      clear()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Later: a tab switch replays.
  const last = useRef(replay)
  useEffect(() => {
    if (last.current === replay) return
    last.current = replay
    if (reducedMotion()) {
      setPhase('static')
      setShown(lines.length)
      return
    }
    play()
    return clear
  }, [replay, play, lines.length])

  return (
    <div className="run ink" data-phase={phase} data-tone={tone} ref={ref}>
      <div className="run__cmd">
        <span className="run__prompt" aria-hidden>
          $
        </span>
        <span>{command}</span>
        {phase === 'busy' && <span className="run__busy">compiling</span>}
      </div>
      <pre className="run__out">
        {lines.map((line, i) => (
          <span key={i} className="run__line" data-shown={i < shown}>
            {line}
            {'\n'}
          </span>
        ))}
      </pre>
    </div>
  )
}
