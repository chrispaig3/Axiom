import { Fragment } from 'react'
import { DOC_LINKS, REPO } from '../data/site.ts'
import { Code } from '../components/Code.tsx'
import { Command } from '../components/Command.tsx'
import { ArrowUpRight } from '../components/Icons.tsx'

/**
 * Verified against a compiler built from this tree:
 *   AXIOM_STDLIB=./stdlib /tmp/axc/axc run hello.ax  -> Hello, Axiom!
 */
const HELLO = `(import IO)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println "Hello, Axiom!")
    0
  }
)`

const CLI: [string, string][] = [
  ['axiom run f.ax', 'compile and execute in one step'],
  ['axiom build --input f.ax --output f', 'a native binary that depends on nothing'],
  ['axiom check f.ax', 'type-check, no code generation'],
  ['axiom test tests/', 'run every test in a file or a directory'],
  ['axiom explain AX3001', 'the full explanation behind any code'],
]

export function Start() {
  return (
    <section className="section section--alt" id="start" aria-labelledby="start-h">
      <div className="container">
        <div className="lede-block">
          <span className="index">07</span>
          <h2 id="start-h">Two prerequisites, then one command.</h2>
          <p>
            You need <code>llc</code> from LLVM and a C compiler for the final
            link. That is the whole list — Axiom's compiler is written in Axiom,
            so there is no other toolchain to install first. The installer is at
            the top of this page; if you would rather build from source, that
            is what a contributor does.
          </p>
        </div>

        <div className="start">
          <div className="start__col">
            <h3>Build from source</h3>
            <p>
              <code>bootstrap/</code> holds the compiler's own LLVM IR, one file
              per host it can build on, committed — so this needs nothing but
              the two prerequisites above.
            </p>
            <Command command="git clone https://github.com/chrispaig3/Axiom && cd Axiom" />
            <Command command="./scripts/bootstrap-from-seed.sh --install .axiom-bin" />
          </div>

          <div className="start__col">
            <h3>Write something</h3>
            <p>
              <code>IO</code> is Axiom's own standard library, so the compiled
              binary calls no C function at all — and the{' '}
              <code>;@axiom:effect(io)</code> line is checked, not decorative.
            </p>
            <Code code={HELLO} name="hello.ax" badge="Hello, Axiom!" />
          </div>

          <div className="start__col">
            <h3>The commands you will use</h3>
            <dl className="cli">
              {CLI.map(([cmd, desc]) => (
                <Fragment key={cmd}>
                  <dt>
                    <code>{cmd}</code>
                  </dt>
                  <dd>{desc}</dd>
                </Fragment>
              ))}
            </dl>
          </div>
        </div>

        <div className="doclinks">
          <h3>Then read the reference.</h3>
          <ul>
            {DOC_LINKS.map((d) => (
              <li key={d.name}>
                <a href={d.href} target="_blank" rel="noreferrer noopener">
                  {d.name}
                  <ArrowUpRight size={11} />
                </a>
                <span>{d.desc}</span>
              </li>
            ))}
          </ul>
          <p className="micro">
            Everything else — the FFI, macros, the language server, the gate
            battery — is in{' '}
            <a href={REPO} target="_blank" rel="noreferrer noopener">
              the repository
            </a>
            .
          </p>
        </div>
      </div>
    </section>
  )
}
