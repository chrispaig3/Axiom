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

          <h1>A functional systems language for humans and agents.</h1>

          <p className="hero__lede">
            S-expressions, a Hindley–Milner-inspired type system, and an LLVM
            backend that emits native executables — no VM, no runtime, no libc.
            The compiler is written in Axiom.
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
