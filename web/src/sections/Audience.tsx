import { BLOB, DOCS } from '../data/site.ts'
import { Reveal } from '../components/Reveal.tsx'
import type { ReactNode } from 'react'

interface Column {
  k: string
  head: string
  body: ReactNode
  points: ReactNode[]
}

const COLUMNS: Column[] = [
  {
    k: 'systems',
    head: 'Systems work',
    body: (
      <>
        The binary is the program. Memory comes from a bump allocator over{' '}
        <code>mmap</code> that the compiler emits into your executable, and I/O
        is the syscall — there is no allocator to tune, no collector to pause
        for, and no runtime to initialise.
      </>
    ),
    points: [
      <>
        Six supported targets, and <code>--target</code> cross-compiles to any of
        them from any host — the target picks the syscall ABI, not the machine
        doing the compiling.
      </>,
      <>
        Explicit arena reclamation where peak memory matters, specified rule by
        rule in{' '}
        <a href={`${DOCS}/memory-model.md`} target="_blank" rel="noreferrer noopener">
          the memory model
        </a>
        .
      </>,
      <>
        Rust interop when you want it: an <code>extern</code> block names symbols
        in a static archive, and one flag builds the crate on the far side.
      </>,
    ],
  },
  {
    k: 'security',
    head: 'Security-sensitive code',
    body: (
      <>
        A smaller program is a smaller thing to audit, and Axiom's is smaller in
        the way that counts: nothing is resolved at load time, and what a
        function is allowed to do can be written down and <em>checked</em> rather
        than reviewed by eye.
      </>
    ),
    points: [
      <>
        <code>;@axiom:restrict(no-io,no-alloc,no-foreign,no-recursion,…)</code> is
        verified against the effect row and the call graph. A violation names the
        path of resolved calls to where the effect enters.
      </>,
      <>
        A function that performs I/O and does not say so is an error, not a
        lint — so silence about effects is a checked claim.
      </>,
      <>
        The compiler refuses input that would escape its own boundaries: a module
        path containing <code>/</code>, and an <code>extern</code> library name
        that could close an IR comment. Both were{' '}
        <em>measured exploits first</em>, then codes and fixtures.
      </>,
    ],
  },
  {
    k: 'agents',
    head: 'Agent-written code',
    body: (
      <>
        Axiom was designed on the assumption that much of its code would be
        written by machines. One syntactic form means no parsing edge cases; a
        dense success-path notation means an agent can ask what a file provides
        without re-reading it.
      </>
    ),
    points: [
      <>
        One greppable line per diagnostic, carrying the fix as a span and a
        replacement — applied by byte-range substitution, not by parsing English.
      </>,
      <>
        One line per <em>symbol</em>, with a content-derived id that survives
        reordering and reformatting, so a tool can address a declaration that
        moved.
      </>,
      <>
        The standard library reads that stream too:{' '}
        <a
          href={`${BLOB}/stdlib/Agent/Tags.ax`}
          target="_blank"
          rel="noreferrer noopener"
        >
          <code>Agent.Tags</code>
        </a>{' '}
        parses AXSYM rather than reaching into the compiler's internals.
      </>,
    ],
  },
]

export function Audience() {
  return (
    <section className="section section--alt" id="for" aria-labelledby="for-h">
      <div className="container">
        <Reveal className="lede-block">
          <span className="index">05</span>
          <h2 id="for-h">Three kinds of work it was built for.</h2>
        </Reveal>

        <div className="cols">
          {COLUMNS.map((c, i) => (
            <Reveal className="cols__col" key={c.k} delay={i * 50}>
              <h3>{c.head}</h3>
              <p>{c.body}</p>
              <ul>
                {c.points.map((p, j) => (
                  <li key={j}>{p}</li>
                ))}
              </ul>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  )
}
