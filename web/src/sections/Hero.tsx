import { HERO } from '../data/samples.ts'
import { INSTALL_CMD, REPO, stat, VERSION } from '../data/site.ts'
import { Code, RunOutput } from '../components/Code.tsx'
import { Command } from '../components/Command.tsx'
import { ArrowRight, GitHub } from '../components/Icons.tsx'

/**
 * Centred hero, program below.
 *
 * The split layout (copy left, a 30-line program right) put the primary
 * action under the fold on a 1366x600 laptop: headline, lede, the
 * install line and only then the buttons. A hero has to answer "what is
 * this, who is it for, what do I do next" in the first screen, so the
 * copy is one column, the two actions sit directly under one sentence
 * of lede, and the program - the product shot - follows, where it can
 * be as tall as it needs to be. The proof strip is the trust bar
 * between the two.
 */
export function Hero() {
  return (
    <section className="hero" id="top">
      <div className="container">
        <div className="hero__lead">
          <p className="hero__kicker">
            <a
              href={`${REPO}/releases/tag/v${VERSION}`}
              target="_blank"
              rel="noreferrer noopener"
            >
              v{VERSION}
            </a>
            <span>MIT</span>
            <span>six targets</span>
            <span>no runtime</span>
          </p>

          <h1>Functional programming that ships a binary, not a runtime.</h1>

          <p className="hero__lede">
            Algebraic data types, exhaustive matching and an effect system the
            compiler <em>checks</em>, lowered through LLVM to a native
            executable with no VM, no collector and no libc inside it.
          </p>

          <div className="hero__actions">
            <a className="btn btn--primary btn--lg" href="#start">
              Get started
              <ArrowRight />
            </a>
            <a
              className="btn btn--ghost btn--lg"
              href={REPO}
              target="_blank"
              rel="noreferrer noopener"
            >
              <GitHub />
              GitHub
            </a>
          </div>

          <div className="hero__install">
            <Command command={INSTALL_CMD} />
          </div>
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
            <b>{stat('lines')}</b>
            <span>
              lines of Axiom that compile Axiom — and rebuild themselves
              byte-for-byte.
            </span>
          </li>
        </ul>

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
