import {
  Fragment,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { highlight, type Token } from '../lib/highlight.ts'
import { ArrowUpRight } from './Icons.tsx'

const cls = (capture: Token['capture']) => `tok-${capture.replace(/\./g, '-')}`

function Highlighted({ code }: { code: string }) {
  const tokens = useMemo(() => highlight(code), [code])
  return (
    <>
      {tokens.map((t, i) =>
        t.capture === 'text' ? (
          <Fragment key={i}>{t.text}</Fragment>
        ) : (
          <span key={i} className={cls(t.capture)}>
            {t.text}
          </span>
        ),
      )}
    </>
  )
}

/**
 * Split the token stream into lines.
 *
 * The gutter used to be a sibling column, and a sibling has its own font
 * and therefore its own line box — which is how the numbers came to sit
 * beside the wrong lines on a narrow screen. A number rendered INSIDE
 * the line it numbers cannot do that: there is one line box, and both
 * halves are in it. Alignment stops being something to keep true.
 */
function toLines(tokens: Token[]): Token[][] {
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

/** Highlighted code, one `<span>` per line, each carrying its number. */
function NumberedCode({ code }: { code: string }) {
  const lines = useMemo(() => toLines(highlight(code)), [code])
  const width = `${String(lines.length).length}ch`
  return (
    <code style={{ ['--ln-w' as string]: width }}>
      {lines.map((line, i) => (
        <span className="ln" key={i}>
          <span className="ln__n" aria-hidden>
            {i + 1}
          </span>
          {line.map((t, j) =>
            t.capture === 'text' ? (
              <Fragment key={j}>{t.text}</Fragment>
            ) : (
              <span key={j} className={cls(t.capture)}>
                {t.text}
              </span>
            ),
          )}
          {'\n'}
        </span>
      ))}
    </code>
  )
}

const reducedMotion = () =>
  typeof matchMedia === 'function' &&
  matchMedia('(prefers-reduced-motion: reduce)').matches

/**
 * The run strip: a prompt, a brief compile beat, then the program's real
 * output a line at a time.
 *
 * The delay is theatre and is labelled as such — it is not a measured
 * compile time, and the benchmark section carries the number that is.
 * It exists because a static block of green text does not read as
 * *output*; watching it arrive does. Under `prefers-reduced-motion` the
 * whole sequence collapses to the finished state, and the text is in the
 * DOM either way, so a screen reader never waits for an animation.
 */
export function RunOutput({ tab, output }: { tab: string; output: string }) {
  const lines = useMemo(() => output.split('\n'), [output])
  const [shown, setShown] = useState(() => (reducedMotion() ? lines.length : 0))
  const [busy, setBusy] = useState(() => !reducedMotion())
  const timers = useRef<number[]>([])

  useEffect(() => {
    for (const t of timers.current) window.clearTimeout(t)
    timers.current = []

    if (reducedMotion()) {
      setShown(lines.length)
      setBusy(false)
      return
    }

    setShown(0)
    setBusy(true)
    timers.current.push(
      window.setTimeout(() => setBusy(false), 420),
      ...lines.map((_, i) =>
        window.setTimeout(() => setShown(i + 1), 460 + i * 130),
      ),
    )
    return () => {
      for (const t of timers.current) window.clearTimeout(t)
    }
  }, [tab, lines])

  return (
    <div className="code__out" data-busy={busy}>
      <span className="code__out-label">
        <span className="code__out-prompt">$</span> axiom run {tab}
      </span>
      <pre>
        {busy ? (
          <span className="code__out-busy">compiling…</span>
        ) : (
          lines.map((line, i) => (
            <span
              key={i}
              className="code__out-line"
              data-shown={i < shown}
            >
              {line}
              {'\n'}
            </span>
          ))
        )}
      </pre>
    </div>
  )
}

interface CodeProps {
  code: string
  name?: string
  badge?: string
  caption?: ReactNode
  /** `false` renders plain — for terminal output, not source. */
  axiom?: boolean
  wrap?: boolean
  tight?: boolean
  /** Show the line-number gutter. */
  numbered?: boolean
  label?: string
}

export function Code({
  code,
  name,
  badge,
  caption,
  axiom = true,
  wrap = false,
  tight = false,
  numbered = false,
  label,
}: CodeProps) {
  const classes = ['code']
  if (wrap) classes.push('code--wrap')
  if (tight) classes.push('code--tight')

  return (
    <figure className={classes.join(' ')} style={{ margin: 0 }}>
      {(name || badge) && (
        <div className="code__bar">
          {name && <span className="code__name">{name}</span>}
          {badge && <span className="code__badge">{badge}</span>}
        </div>
      )}
      <div className={numbered ? 'code__body code__body--numbered' : 'code__body'}>
        <pre aria-label={label}>
          {numbered && axiom ? (
            <NumberedCode code={code} />
          ) : (
            <code>{axiom ? <Highlighted code={code} /> : code}</code>
          )}
        </pre>
      </div>
      {caption && <figcaption className="code__caption">{caption}</figcaption>}
    </figure>
  )
}

export interface TabbedItem {
  id: string
  tab: string
  code: string
  /** Real program output, shown under the source. */
  output?: string
  caption?: ReactNode
}

/** Programs longer than this open folded, so the page is not one scroll
    of source between two headings. The fold is announced and one
    control opens it; the whole program is in the DOM either way. */
const FOLD_AT = 34

export function TabbedCode({
  items,
  label,
}: {
  items: TabbedItem[]
  label: string
}) {
  const [active, setActive] = useState(0)
  const [expanded, setExpanded] = useState(false)
  const uid = useId()
  const current = items[active] ?? items[0]
  if (!current) return null

  const lineCount = current.code.split('\n').length
  const folded = lineCount > FOLD_AT && !expanded

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return
    e.preventDefault()
    const delta = e.key === 'ArrowRight' ? 1 : -1
    const next = (active + delta + items.length) % items.length
    setActive(next)
    setExpanded(false)
    document.getElementById(`${uid}-tab-${next}`)?.focus()
  }

  return (
    <div className="code code--program">
      <div className="code__bar">
        <div
          className="code__tabs"
          role="tablist"
          aria-label={label}
          onKeyDown={onKeyDown}
        >
          {items.map((item, i) => (
            <button
              key={item.id}
              id={`${uid}-tab-${i}`}
              className="code__tab"
              type="button"
              role="tab"
              aria-selected={i === active}
              aria-controls={`${uid}-panel-${i}`}
              tabIndex={i === active ? 0 : -1}
              onClick={() => {
                setActive(i)
                setExpanded(false)
              }}
            >
              {item.tab}
            </button>
          ))}
        </div>
      </div>

      <div
        className={
          folded
            ? 'code__body code__body--numbered code__body--folded'
            : 'code__body code__body--numbered'
        }
        id={`${uid}-panel-${active}`}
        role="tabpanel"
        aria-labelledby={`${uid}-tab-${active}`}
        tabIndex={0}
      >
        <pre>
          <NumberedCode code={current.code} />
        </pre>
      </div>

      {lineCount > FOLD_AT && (
        <div className="code__fold">
          <button
            type="button"
            className="code__fold-btn"
            onClick={() => setExpanded((e) => !e)}
            aria-expanded={!folded}
            aria-controls={`${uid}-panel-${active}`}
          >
            {folded ? `Show all ${lineCount} lines` : 'Fold the program'}
          </button>
        </div>
      )}

      {current.output && (
        <RunOutput
          key={current.id}
          tab={current.tab}
          output={current.output}
        />
      )}

      {current.caption && <div className="code__caption">{current.caption}</div>}
    </div>
  )
}

/** A repo path rendered as a link to the file on GitHub. */
export function SourceLink({ path, href }: { path: string; href: string }) {
  return (
    <a href={href} target="_blank" rel="noreferrer noopener">
      {path}
      <ArrowUpRight size={11} />
    </a>
  )
}
