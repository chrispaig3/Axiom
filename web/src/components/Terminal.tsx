import { Fragment, useId, useState, type ReactNode } from 'react'

/**
 * Compiler output, coloured.
 *
 * README.md says the real report is coloured — "severity and carets in
 * the severity's colour, the gutter blue, the `= help:` marker green" —
 * and that the palette is one table in `self_host/style.ax`. The text
 * here is quoted exactly; the colour is applied by this file, because a
 * web page is not a terminal any more than a markdown fence is.
 */

type Piece = { t: string; c?: string }

function push(out: Piece[], t: string, c?: string) {
  if (t) out.push(c ? { t, c } : { t })
}

function paint(pieces: Piece[]) {
  return pieces.map((p, i) =>
    p.c ? (
      <span key={i} className={p.c}>
        {p.t}
      </span>
    ) : (
      <Fragment key={i}>{p.t}</Fragment>
    ),
  )
}

/** One line of a rustc-flavoured human report. */
function humanLine(line: string): Piece[] {
  const out: Piece[] = []

  const head = /^(error|warning)(\[[A-Z]{2}\d{4}\])(:)(.*)$/.exec(line)
  if (head) {
    const sev = head[1] === 'warning' ? 'term-w' : 'term-e'
    push(out, head[1] ?? '', sev)
    push(out, head[2] ?? '', 'term-code')
    push(out, head[3] ?? '', sev)
    push(out, head[4] ?? '')
    return out
  }

  const loc = /^(\s*-->\s*)(.*)$/.exec(line)
  if (loc) {
    push(out, loc[1] ?? '', 'term-gutter')
    push(out, loc[2] ?? '', 'term-dim')
    return out
  }

  const help = /^(\s*)(=)(\s*)(help|note):(.*)$/.exec(line)
  if (help) {
    push(out, help[1] ?? '')
    push(out, help[2] ?? '', 'term-gutter')
    push(out, help[3] ?? '')
    push(out, `${help[4]}:`, 'term-help')
    // `~>` introduces a machine-applicable replacement; mark it so the
    // suggestion reads as a suggestion and not as prose.
    const rest = help[5] ?? ''
    const fix = rest.indexOf('~>')
    if (fix >= 0) {
      push(out, rest.slice(0, fix))
      push(out, '~>', 'term-help')
      push(out, rest.slice(fix + 2), 'term-str')
    } else {
      push(out, rest)
    }
    return out
  }

  // The window marker between two quoted spans.
  if (/^\s*\.\.\.\s*$/.test(line)) {
    push(out, line, 'term-gutter')
    return out
  }

  const gutter = /^(\s*\d*\s*)(\|)(.*)$/.exec(line)
  if (gutter) {
    push(out, gutter[1] ?? '', 'term-gutter')
    push(out, gutter[2] ?? '', 'term-gutter')
    const rest = gutter[3] ?? ''
    const caret = /^(\s*)(\^+|-+)(.*)$/.exec(rest)
    if (caret) {
      push(out, caret[1] ?? '')
      push(out, caret[2] ?? '', caret[2]?.startsWith('^') ? 'term-e' : 'term-gutter')
      push(out, caret[3] ?? '', 'term-dim')
    } else {
      push(out, rest)
    }
    return out
  }

  if (line.startsWith('compilation failed')) {
    push(out, line, 'term-dim')
    return out
  }

  push(out, line)
  return out
}

/**
 * An AXDL line, coloured by field. Reading order is fixed — severity,
 * code, file and span, slug, message, then `#` label, `^` related, `!`
 * note, `?` help and `&` macro frame — so a token's sigil is its role.
 */
function axdlLine(line: string): Piece[] {
  const out: Piece[] = []
  const m = /^([EW])( )(AX\d{4})( )(\S+)( )([a-z0-9-]+)( )(.*)$/.exec(line)
  if (!m) return [{ t: line }]

  push(out, m[1] ?? '', m[1] === 'W' ? 'term-w' : 'term-e')
  push(out, m[2] ?? '')
  push(out, m[3] ?? '', 'term-code')
  push(out, m[4] ?? '')
  push(out, m[5] ?? '', 'term-gutter')
  push(out, m[6] ?? '')
  push(out, m[7] ?? '', 'term-key')
  push(out, m[8] ?? '')

  const tail = m[9] ?? ''
  const re = /("(?:[^"\\]|\\.)*")|([#^!?&])|(~>)|([^"#^!?&~]+)/g
  let t: RegExpExecArray | null
  while ((t = re.exec(tail)) !== null) {
    if (t[1]) push(out, t[1], 'term-str')
    else if (t[2]) push(out, t[2], 'term-key')
    else if (t[3]) push(out, t[3], 'term-help')
    else push(out, t[4] ?? '', 'term-dim')
  }
  return out
}

/** One AXSYM line: kind letter, name, location, quoted type, nid, metadata. */
function axsymLine(line: string): Piece[] {
  const m = /^([FDCSAEM])( )(\S+)( )(\S+)( )(.*)$/.exec(line)
  if (!m) return [{ t: line }]

  const out: Piece[] = [
    { t: m[1] ?? '', c: 'term-w' },
    { t: m[2] ?? '' },
    { t: m[3] ?? '', c: 'tok-function' },
    { t: m[4] ?? '' },
    { t: m[5] ?? '', c: 'term-gutter' },
    { t: m[6] ?? '' },
  ]

  const re = /("(?:[^"\\]|\\.)*")|(@[0-9a-f]+)|(#[^\s]+)|(\s+)/g
  let t: RegExpExecArray | null
  const rest = m[7] ?? ''
  while ((t = re.exec(rest)) !== null) {
    if (t[1]) push(out, t[1], 'term-str')
    else if (t[2]) push(out, t[2], 'term-help')
    else if (t[3]) push(out, t[3], 'term-key')
    else push(out, t[4] ?? '')
  }
  return out
}

/** A JSON Lines object: keys violet, strings green, numbers warm. */
function jsonLine(line: string): Piece[] {
  const out: Piece[] = []
  const re = /("(?:[^"\\]|\\.)*")(\s*:)?|(-?\d+(?:\.\d+)?)|([^"\d-]+|-)/g
  let m: RegExpExecArray | null
  while ((m = re.exec(line)) !== null) {
    if (m[1] && m[2]) {
      push(out, m[1], 'term-key')
      push(out, m[2], 'term-dim')
    } else if (m[1]) {
      push(out, m[1], 'term-str')
    } else if (m[3]) {
      push(out, m[3], 'term-num')
    } else {
      push(out, m[4] ?? '', 'term-dim')
    }
  }
  return out
}

export type RenderKind = 'human' | 'axdl' | 'axsym' | 'json' | 'plain'

const LINE_FN: Record<RenderKind, (l: string) => Piece[]> = {
  human: humanLine,
  axdl: axdlLine,
  axsym: axsymLine,
  json: jsonLine,
  plain: (l) => [{ t: l, c: 'term-dim' }],
}

export interface RenderItem {
  id: string
  tab: string
  kind: RenderKind
  text: string
}

/**
 * A tab strip over two or more renderings of the same compiler output.
 * A real ARIA tablist, because a set of buttons that swaps a panel is a
 * tablist whether or not it says so.
 */
export function RenderTabs({
  items,
  label,
  name,
  caption,
  wrap = true,
}: {
  items: RenderItem[]
  label: string
  name?: string
  caption?: ReactNode
  /** `false` keeps every line on one line and scrolls sideways instead —
      for the aligned table, whose columns are the point. */
  wrap?: boolean
}) {
  const [active, setActive] = useState(0)
  const uid = useId()
  const current = items[active] ?? items[0]
  if (!current) return null

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return
    e.preventDefault()
    const delta = e.key === 'ArrowRight' ? 1 : -1
    const next = (active + delta + items.length) % items.length
    setActive(next)
    document.getElementById(`${uid}-tab-${next}`)?.focus()
  }

  const render = LINE_FN[current.kind]

  return (
    <div className={wrap ? 'code code--wrap code--tight' : 'code code--tight'}>
      <div className="code__bar">
        {name && <span className="code__name">{name}</span>}
        <div
          className="code__tabs"
          role="tablist"
          aria-label={label}
          onKeyDown={onKeyDown}
          style={name ? { marginLeft: 'auto' } : undefined}
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
              onClick={() => setActive(i)}
            >
              {item.tab}
            </button>
          ))}
        </div>
      </div>
      <div
        className="code__body"
        id={`${uid}-panel-${active}`}
        role="tabpanel"
        aria-labelledby={`${uid}-tab-${active}`}
        tabIndex={0}
      >
        <pre>
          <code>
            {current.text.split('\n').map((line, i) => (
              <Fragment key={i}>
                {paint(render(line))}
                {'\n'}
              </Fragment>
            ))}
          </code>
        </pre>
      </div>
      {caption && <div className="code__caption">{caption}</div>}
    </div>
  )
}
