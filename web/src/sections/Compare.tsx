import { REPO } from '../data/site.ts'
import { Reveal } from '../components/Reveal.tsx'
import type { ReactNode } from 'react'

/**
 * A design comparison, not a benchmark.
 *
 * Every Axiom cell is sourced: the runtime row is `docs/memory-model.md`
 * MM-ALLOC-1/2 (gated by `scripts/check-freestanding.sh`); the effects
 * row is `docs/reference.md` (Effects) and `docs/diagnostics.md`
 * (AX3010/AX3049); the syntax row is `docs/macro-system.md`; the
 * tooling row is `docs/diagnostics.md` (AXDL/AXSYM/NID); the build row
 * is `docs/reference.md` (Packages).
 *
 * The other columns are restricted to facts that are not in dispute —
 * that Go and GHC ship a garbage collector and a runtime, that a Rust
 * binary using `std` links libc, that neither Rust nor Go tracks
 * effects. Nothing here scores anybody.
 */
interface Row {
  k: string
  axiom: ReactNode
  rust: string
  go: string
  haskell: string
}

const ROWS: Row[] = [
  {
    k: 'How memory is managed',
    axiom: (
      <>
        <strong>A bump allocator over <code>mmap</code></strong>, with explicit
        arena reclamation where peak memory matters. No tracing collector, and no
        borrow checker to satisfy.
      </>
    ),
    rust: 'ownership and borrowing',
    go: 'tracing GC',
    haskell: 'tracing GC',
  },
  {
    k: 'Whether effects are tracked',
    axiom: (
      <>
        <strong>Inferred per function, and checkable from source.</strong>{' '}
        <code>;@axiom:effect(io)</code> above a declaration is a claim the
        compiler tests against what the body actually reaches — and a false one
        is an error.
      </>
    ),
    rust: 'not tracked',
    go: 'not tracked',
    haskell: 'tracked, written by hand',
  },
  {
    k: 'What a macro operates on',
    axiom: (
      <>
        <strong>The program tree itself</strong>, because the syntax is already a
        tree. Expansion runs before the type checker, so everything a macro
        generates is checked like anything else.
      </>
    ),
    rust: 'token streams',
    go: 'no macros',
    haskell: 'Template Haskell',
  },
  {
    k: 'What it takes to build and run',
    axiom: (
      <>
        <strong>
          <code>axiom run f.ax</code>
        </strong>
        . One step, one binary, no build file. A dependency is a path on your
        machine — there is no registry to configure and no lockfile to resolve.
      </>
    ),
    rust: 'cargo and crates.io',
    go: 'go build and modules',
    haskell: 'cabal or stack',
  },
]

export function Compare() {
  return (
    <section className="section" id="compare" aria-labelledby="compare-h">
      <div className="container">
        <Reveal className="lede-block">
          <span className="index">04</span>
          <h2 id="compare-h">
            Four decisions that set it apart.
          </h2>
          <p>
            Design, not benchmarks — the numbers are one section up. Every Axiom
            cell here is held by something in the repository; the other columns
            are restricted to facts nobody disputes.
          </p>
        </Reveal>

        <Reveal className="matrix">
          {ROWS.map((r) => (
            <article className="matrix__row" key={r.k}>
              <h3 className="matrix__k">{r.k}</h3>
              <p className="matrix__ax">{r.axiom}</p>
              <ul className="matrix__others">
                <li>
                  <span>Rust</span>
                  {r.rust}
                </li>
                <li>
                  <span>Go</span>
                  {r.go}
                </li>
                <li>
                  <span>Haskell</span>
                  {r.haskell}
                </li>
              </ul>
            </article>
          ))}
        </Reveal>

        <Reveal className="closing" delay={60}>
          <p>
            Axiom is <code>0.x</code>. The feature-by-feature status table — what
            is complete, what is partial, what was removed, each with the test
            that holds it — is{' '}
            <a
              href={`${REPO}#implementation-status`}
              target="_blank"
              rel="noreferrer noopener"
            >
              in the README
            </a>
            , and nothing on this page is a promise that table does not make.
          </p>
        </Reveal>
      </div>
    </section>
  )
}
