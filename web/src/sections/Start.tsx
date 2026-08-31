import { DOC_LINKS, INSTALL_CMD, REPO } from '../data/site.ts'
import { Code } from '../components/Code.tsx'
import { Command } from '../components/Command.tsx'
import { ArrowUpRight } from '../components/Icons.tsx'
import { Reveal } from '../components/Reveal.tsx'

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

const CLI = [
  ['axiom run f.ax', 'compile and execute in one step'],
  ['axiom build --input f.ax --output f', 'a native executable that depends on nothing'],
  ['axiom check f.ax', 'type-check, no code generation'],
  ['axiom explain AX3001', 'the full explanation behind any code'],
]

export function Start() {
  return (
    <section className="section section--alt" id="start" aria-labelledby="start-h">
      <div className="container">
        <div className="split split--narrow">
          <Reveal className="lede-block">
            <span className="index">07</span>
            <h2 id="start-h">Two prerequisites, then one command.</h2>
            <p>
              You need <code>llc</code> from LLVM and a C compiler for the final
              link. That is the whole list — Axiom's compiler is written in
              Axiom, so there is no other toolchain to install first.
            </p>
          </Reveal>

          <Reveal className="stack">
            <Command command={INSTALL_CMD} />
            <p className="micro">
              Verifies the archive's SHA-256, then builds and runs a program that
              imports a standard-library module before reporting success. Prefer
              source? <code>./scripts/bootstrap-from-seed.sh --install .axiom-bin</code>{' '}
              works on every target.
            </p>

            <Code code={HELLO} name="hello.ax" badge="axiom run hello.ax" />

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
          </Reveal>
        </div>

        <div className="rule" />

        <Reveal className="doclinks">
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
        </Reveal>
      </div>
    </section>
  )
}

import { Fragment } from 'react'
