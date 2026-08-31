import { HERO } from '../data/samples.ts'
import { INSTALL_CMD, REPO, VERSION } from '../data/site.ts'
import { Code, RunOutput } from '../components/Code.tsx'
import { Command } from '../components/Command.tsx'
import { ArrowRight, GitHub } from '../components/Icons.tsx'

export function Hero() {
  return (
    <section className="hero" id="top">
      <div className="container hero__inner">
        <div className="hero__lead">
          {/* No logo lockup here. The mark is in the nav, which is where a
              wordmark belongs; a dark image plate floating above the
              headline was the one element on the page that answered to no
              rule the rest of it follows. */}
          <p className="hero__kicker">
            Axiom <span>v{VERSION}</span>
          </p>

          <h1>
            Functional programming that ships a binary, not a runtime.
          </h1>

          <p className="hero__lede">
            Algebraic data types, exhaustive matching and an effect system the
            compiler <em>checks</em> — lowered through LLVM to a native
            executable with no VM, no collector and no libc inside it. Written
            in itself, for the humans and the agents that will write the rest.
          </p>

          <Command command={INSTALL_CMD} />

          <div className="hero__actions">
            <a className="btn btn--primary" href="#start">
              Get started
              <ArrowRight />
            </a>
            <a
              className="btn btn--ghost"
              href={REPO}
              target="_blank"
              rel="noreferrer noopener"
            >
              <GitHub />
              GitHub
            </a>
            <span className="hero__meta">MIT · six supported targets</span>
          </div>

          <ul className="proof">
            <li>
              <b>0</b>
              <span>
                undefined symbols in a compiled program.{' '}
                <a href="#speed">nm -u says so</a>.
              </span>
            </li>
            <li>
              <b>1 ms</b>
              <span>
                separates it from C and Rust on the same loop.{' '}
                <a href="#speed">Measured, not asserted</a>.
              </span>
            </li>
            <li>
              <b>87,494</b>
              <span>
                lines of Axiom that compile Axiom — and rebuild themselves
                byte-for-byte.
              </span>
            </li>
          </ul>
        </div>

        <div className="hero__panel">
          <Code
            code={HERO.code}
            name="shapes.ax"
            badge="a whole program"
            numbered
          />
          <RunOutput tab="shapes.ax" output={HERO.result ?? ''} />
        </div>
      </div>
    </section>
  )
}
