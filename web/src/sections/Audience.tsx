import { BLOB, DOCS } from '../data/site.ts'
import { ArrowRight } from '../components/Icons.tsx'
import { Reveal } from '../components/Reveal.tsx'
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
        <b>Six targets, one flag.</b> <code>--target</code> cross-compiles from
        any host: the target picks the syscall ABI, not the machine you are
        sitting at.
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
        <b>No load-time surface.</b> Nothing is resolved when the program
        starts, so there is no dynamic linker to influence.
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
        <b>Addresses that survive an edit.</b> Every declaration carries a
        content-derived id that does not move when the file is reordered or
        reformatted.
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
        <Reveal className="lede-block">
          <span className="index">05</span>
          <h2 id="for-h">Three kinds of work it was built for.</h2>
          <p>
            Axiom is small on purpose, and the places that pays off are the ones
            where a runtime you did not write is a liability.
          </p>
        </Reveal>

        <div className="cols">
          {COLUMNS.map((c, i) => (
            <Reveal className="cols__col" key={c.k} delay={i * 50}>
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
            </Reveal>
          ))}
        </div>

        <Reveal className="closing" delay={80}>
          <p>
            One thing Axiom is <em>not</em> built for, said here rather than
            discovered later: concurrency is one narrow form and no runtime.{' '}
            <code>(parallel p ((a e1) (b e2)) body)</code> runs its bindings
            beside the caller and joins them in argument order — as child
            processes by default, whose isolation is true by construction, or
            as threads under <code>--threads</code>. Only a machine word
            crosses a join; a binding that answers a <code>String</code> is a
            type error at the binding. There is no async, no scheduler, no
            task system, and under threads the compiler does not yet check
            what a binding captures — which is why processes are the default.{' '}
            <a
              href={`${BLOB}/stdlib/Job.ax`}
              target="_blank"
              rel="noreferrer noopener"
            >
              <code>stdlib/Job.ax</code>
            </a>{' '}
            is a bounded pool of child <em>programs</em>, and it is the rest of
            the story.
          </p>
        </Reveal>
      </div>
    </section>
  )
}
