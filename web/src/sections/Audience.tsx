import { BLOB, DOCS } from '../data/site.ts'
import { ArrowRight } from '../components/Icons.tsx'
import type { ReactNode } from 'react'

interface Column {
  k: string
  kicker: string
  head: string
  body: ReactNode
  points: ReactNode[]
  link: { label: string; href: string }
}

const COLUMNS: Column[] = [
  {
    k: 'systems',
    kicker: 'Systems programming',
    head: 'Ship a binary, not a runtime.',
    body: (
      <>
        Your program is the whole artifact. The allocator is emitted into your
        executable, I/O is the syscall, and <code>nm -u</code> on the result
        lists <strong>zero undefined symbols</strong> — nothing to initialise at
        start-up, because there is nothing left to resolve.
      </>
    ),
    points: [
      <>
        <b>Six targets, one flag.</b> <code>--target</code> picks the syscall
        ABI and emits code for any of the six from any host; only the final
        link needs that target's linker.
      </>,
      <>
        <b>Arenas where peak memory matters.</b> Reclamation is explicit and
        specified rule by rule, not inferred and hoped for.
      </>,
      <>
        <b>Rust when you want it.</b> An <code>extern</code> block names symbols
        in a static archive; one flag builds the crate on the far side.
      </>,
    ],
    link: { label: 'Read the memory model', href: `${DOCS}/memory-model.md` },
  },
  {
    k: 'security',
    kicker: 'Security-sensitive code',
    head: 'Say what a function may do. Have it checked.',
    body: (
      <>
        <code>;@axiom:restrict(no-io,no-alloc,no-foreign)</code> is not a
        comment. It is a claim the compiler tests against the effect row and the
        call graph — and when it fails, the message names the exact path of
        calls to where the effect enters.
      </>
    ),
    points: [
      <>
        <b>Silence is a checked claim.</b> A function that performs I/O and does
        not declare it is an error, not a lint you can turn off.
      </>,
      <>
        <b>No load-time surface.</b> <code>nm -u</code> is empty, so there
        is no symbol for a dynamic linker to bind, and nothing to redirect.
      </>,
      <>
        <b>Exploits first, codes second.</b> A traversable module path and an
        injectable linker name were each <em>measured working</em> before they
        became a diagnostic and a fixture.
      </>,
    ],
    link: { label: 'Read the diagnostics guide', href: `${DOCS}/diagnostics.md` },
  },
  {
    k: 'agents',
    kicker: 'Agent-written code',
    head: 'Answer the machine in its own format.',
    body: (
      <>
        Most toolchains publish their failures and keep their successes to
        themselves. Axiom publishes both — one line per diagnostic{' '}
        <em>and</em> one line per symbol — so an agent can ask what a file
        already provides without paying to read it again.
      </>
    ),
    points: [
      <>
        <b>Fixes arrive applicable.</b> A span and a replacement, applied by
        byte-range substitution rather than by parsing English.
      </>,
      <>
        <b>Addresses that survive an edit.</b> Every function, type and
        struct carries a content-derived id that does not move when the file
        is reordered or reformatted.
      </>,
      <>
        <b>One syntactic form.</b> No operator precedence, no parsing edge
        cases — the thing generating the code has less to get wrong.
      </>,
    ],
    link: { label: 'Read the agent harness', href: `${DOCS}/agent-harness.md` },
  },
]

export function Audience() {
  return (
    <section className="section section--alt" id="for" aria-labelledby="for-h">
      <div className="container">
        <div className="lede-block">
          <span className="index">05</span>
          <h2 id="for-h">Three kinds of work it was built for.</h2>
          <p>
            Axiom is small on purpose, and the places that pays off are the ones
            where a runtime you did not write is a liability.
          </p>
        </div>

        <div className="cols">
          {COLUMNS.map((c) => (
            <div className="cols__col" key={c.k}>
              <span className="cols__kicker">{c.kicker}</span>
              <h3>{c.head}</h3>
              <p>{c.body}</p>
              <ul>
                {c.points.map((p, j) => (
                  <li key={j}>{p}</li>
                ))}
              </ul>
              <a
                className="cols__link"
                href={c.link.href}
                target="_blank"
                rel="noreferrer noopener"
              >
                {c.link.label}
                <ArrowRight size={13} />
              </a>
            </div>
          ))}
        </div>

        <div className="closing">
          <p>
            One thing Axiom is <em>not</em> built for, said here rather than
            discovered later: concurrency is one narrow form and no runtime.{' '}
            <a
              href={`${DOCS}/reference.md#parallel--bindings-that-run-beside-the-caller`}
              target="_blank"
              rel="noreferrer noopener"
            >
              <code>parallel</code>
            </a>{' '}
            runs its bindings beside the caller and joins them in the order
            written — as child processes by default, whose isolation is true
            by construction, or as threads under <code>--threads</code>. Only
            a machine word crosses a join, and a binding that captures a
            reference the parent holds is refused under either lowering. There
            is no async, no scheduler and no task system;{' '}
            <a
              href={`${BLOB}/stdlib/Par.ax`}
              target="_blank"
              rel="noreferrer noopener"
            >
              <code>stdlib/Par.ax</code>
            </a>{' '}
            is a bounded pool over the same primitives, and it is the rest of
            the story.
          </p>
        </div>
      </div>
    </section>
  )
}
