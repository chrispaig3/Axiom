import { COMPARE } from '../data/content.ts'
import { DOCS } from '../data/site.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { inline } from '../lib/inline.tsx'

/**
 * A design comparison, not a benchmark. The Axiom column is sourced in
 * `content.ts`; the others are restricted to facts nobody disputes, and
 * nothing here scores anybody. On a narrow screen each row becomes a
 * card rather than a table scrolled sideways, because the Axiom cell is
 * the one that needs room.
 */
export function Compare() {
  return (
    <section className="section" id="compare" aria-labelledby="compare-h">
      <div className="container">
        <SectionHead id="compare-h" eyebrow="How it compares" title="Five decisions that set it apart.">
          <p>
            Design, not benchmarks: the numbers are one section up. Every Axiom cell is held by
            something in the repository; the other columns stick to facts nobody disputes.
          </p>
        </SectionHead>

        <div className="compare" role="table" aria-label="Axiom compared with Rust, Go and Haskell">
          <div className="compare__row compare__row--head" role="row">
            <span role="columnheader" />
            <span role="columnheader" className="compare__ax">
              Axiom
            </span>
            <span role="columnheader">Rust</span>
            <span role="columnheader">Go</span>
            <span role="columnheader">Haskell</span>
          </div>
          {COMPARE.map((r) => (
            <div className="compare__row" role="row" key={r.k}>
              <span role="rowheader" className="compare__k">
                {r.k}
              </span>
              <span role="cell" className="compare__ax" data-label="Axiom">
                {inline(r.axiom)}
              </span>
              <span role="cell" data-label="Rust">
                {r.rust}
              </span>
              <span role="cell" data-label="Go">
                {r.go}
              </span>
              <span role="cell" data-label="Haskell">
                {r.haskell}
              </span>
            </div>
          ))}
        </div>

        <p className="aside">
          Axiom is <code>0.x</code>, and nothing on this page is a promise the{' '}
          <a href={`${DOCS}/status.md#implementation-status`} target="_blank" rel="noreferrer noopener">
            status table
          </a>{' '}
          does not make. The honest summary is <a href="#status">further down</a>.
        </p>
      </div>
    </section>
  )
}
