import { COMPARE } from '../data/content.ts'
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
        <SectionHead id="compare-h" eyebrow="How it compares" title="A different set of tradeoffs.">
          <p>Functional types, explicit effects, and native output in one language. See how Axiom’s choices sit alongside Rust, Go, and Haskell.</p>
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
      </div>
    </section>
  )
}
