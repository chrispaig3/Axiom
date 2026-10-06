import { useId, useState } from 'react'
import { BENCH, BENCH_CMDS, BENCH_ENV, type BenchRow } from '../data/bench.ts'
import { BLOB } from '../data/site.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { Snippet } from '../components/Code.tsx'

/**
 * The benchmark as small multiples.
 *
 * Four measurements on four different scales - seconds, seconds, bytes,
 * a count - so each gets its own chart and its own axis rather than a
 * shared one that would invent a comparison between them. The story in
 * every panel is "Axiom against the other two", so the form is
 * emphasis: Axiom in the accent, Rust and C in a recessive gray, every
 * bar named by its row label so identity never rests on colour alone.
 * The bar colours were run through the dataviz palette validator
 * against both chart surfaces. The table the numbers came from sits
 * under the charts, unchanged, as their table view.
 */

type Lang = 'axiom' | 'rust' | 'c'
const LANGS: { key: Lang; label: string }[] = [
  { key: 'axiom', label: 'Axiom' },
  { key: 'rust', label: 'Rust' },
  { key: 'c', label: 'C' },
]

const num = (s: string) => Number.parseFloat(s.replace(/[^\d.]/g, ''))

/** One sentence per panel, computed from the row so it cannot drift. */
function headline(r: BenchRow): string {
  const ax = num(r.axiom)
  const rust = num(r.rust)
  const c = num(r.c)
  switch (r.metric) {
    case 'Run time': {
      const spread = Math.round((Math.max(ax, rust, c) - Math.min(ax, rust, c)) * 1000)
      return `All three within ${spread} ms`
    }
    case 'Compile to a native binary': {
      const best = Math.min(rust, c)
      return ax > best
        ? `Axiom is the slowest, by ${Math.round((ax - best) * 1000)} ms`
        : 'Axiom is the fastest'
    }
    case 'Binary size':
      return `${Math.round(rust / ax)}× smaller than Rust, ${Math.round((ax / c - 1) * 100)}% over C`
    case 'Undefined symbols':
      return `${r.axiom} for Axiom, ${r.rust} for Rust, ${r.c} for C`
    default:
      return ''
  }
}

function Panel({ r }: { r: BenchRow }) {
  const [hover, setHover] = useState<Lang | null>(null)
  const uid = useId()
  const values = LANGS.map((l) => ({ ...l, text: r[l.key], v: num(r[l.key]) }))
  const max = Math.max(...values.map((x) => x.v)) || 1

  return (
    <figure className="bar-card" aria-labelledby={`${uid}-t`}>
      <figcaption>
        <span className="bar-card__metric" id={`${uid}-t`}>
          {r.metric}
        </span>
        <span className="bar-card__head">{headline(r)}</span>
        <span className="bar-card__how">{r.how}</span>
      </figcaption>
      <div className="bars" role="list">
        {values.map((x) => {
          const pct = (x.v / max) * 100
          return (
            <div
              className="bars__row"
              role="listitem"
              key={x.key}
              data-lang={x.key}
              data-hover={hover === x.key || undefined}
              tabIndex={0}
              aria-label={`${x.label}: ${x.text}`}
              onMouseEnter={() => setHover(x.key)}
              onMouseLeave={() => setHover(null)}
              onFocus={() => setHover(x.key)}
              onBlur={() => setHover(null)}
            >
              <span className="bars__label">{x.label}</span>
              {/* The bar's length is its share of the track, and the track
                  reserves room for the label past its own end - so the
                  longest bar and a nearly-as-long one stay in proportion
                  rather than both being capped to the same width. */}
              <span className="bars__track" style={{ ['--pct' as string]: `${pct}%` }}>
                <span className="bars__bar" data-zero={x.v === 0 || undefined} />
                <span className="bars__value">{x.text}</span>
              </span>
              {hover === x.key && (
                <span className="bars__tip" role="tooltip">
                  <b>{x.text}</b>
                  <span>
                    {x.label} · {r.metric.toLowerCase()}
                  </span>
                </span>
              )}
            </div>
          )
        })}
      </div>
      <p className="bar-card__note">{r.note}</p>
    </figure>
  )
}

export function Benchmark() {
  return (
    <section className="section" id="speed" aria-labelledby="speed-h">
      <div className="container">
        <SectionHead id="speed-h" eyebrow="Performance" title="Small binaries. Measured performance.">
          <p>
            In this Collatz benchmark, Axiom runs within milliseconds of C and Rust, with a binary
            close to C’s size. One workload, one machine, with the source and method available
            for you to reproduce.
          </p>
        </SectionHead>

        <div className="bench-grid">
          {BENCH.map((r) => (
            <Panel key={r.metric} r={r} />
          ))}
        </div>

        <p className="bench-env">
          {BENCH_ENV.machine} · {BENCH_ENV.axiom} · {BENCH_ENV.rust} · {BENCH_ENV.c} · timed with{' '}
          {BENCH_ENV.timer}. All three print <code>{BENCH_ENV.answer}</code>.
        </p>

        <details className="method">
          <summary>How it was measured, and the table behind the charts</summary>
          <div className="method__body">
            <div className="method__text">
              <p>
                Collatz step counts for 1..3,000,000, summed and printed. Signed 64-bit integers, no
                allocation, no library call in the hot loop. Each figure is the <strong>best</strong>{' '}
                of its runs, not the mean: interference only ever makes a run slower, so the minimum
                is the closest estimate of the cost itself.
              </p>
              <p>
                The runs are <strong>interleaved</strong>, one repetition of each binary in turn, and
                that correction changed the answer. A first pass that ran each binary in a block put
                Axiom 1.6&times; behind Rust. It was an artefact: a background build starting midway
                taxes whichever block it lands on. Alternating gives every binary the same
                interference, and the three collapse onto each other.
              </p>
              <p>
                The three programs are in the repository, in{' '}
                <a href={`${BLOB}/web/bench`} target="_blank" rel="noreferrer noopener">
                  <code>web/bench/</code>
                </a>
                , and <code>run-bench.sh</code> beside them produces every cell of this table, so it
                can be re-run rather than taken on trust. Go and Haskell are absent because no
                toolchain for either was on the machine, and this project publishes only numbers
                it has measured. One micro-benchmark says nothing about allocation-heavy work,
                which{' '}
                <a
                  href={`${BLOB}/scripts/bench-datastructures.sh`}
                  target="_blank"
                  rel="noreferrer noopener"
                >
                  <code>scripts/bench-datastructures.sh</code>
                </a>{' '}
                measures separately, and less flatteringly.
              </p>
              <Snippet code={BENCH_CMDS} />
            </div>
            <div className="table-wrap" tabIndex={0} role="group" aria-label="Benchmark table">
              <table className="bench-table">
                <caption className="visually-hidden">
                  Run time, compile time, binary size and undefined symbol count for the same
                  Collatz workload in Axiom, Rust and C.
                </caption>
                <thead>
                  <tr>
                    <th scope="col">Measurement</th>
                    <th scope="col">Axiom</th>
                    <th scope="col">Rust</th>
                    <th scope="col">C</th>
                  </tr>
                </thead>
                <tbody>
                  {BENCH.map((r) => (
                    <tr key={r.metric}>
                      <th scope="row">
                        {r.metric}
                        <span>{r.how}</span>
                      </th>
                      <td className="is-ax">{r.axiom}</td>
                      <td>{r.rust}</td>
                      <td>{r.c}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </details>
      </div>
    </section>
  )
}
