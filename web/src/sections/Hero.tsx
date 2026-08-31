import { asset } from '../lib/asset.ts'
import { HERO } from '../data/samples.ts'
import { INSTALL_CMD, REPO, VERSION } from '../data/site.ts'
import { Code } from '../components/Code.tsx'
import { Command } from '../components/Command.tsx'
import { ArrowRight, GitHub } from '../components/Icons.tsx'

export function Hero() {
  return (
    <section className="hero" id="top">
      <div className="container hero__inner">
        <div className="hero__lead">
          <span className="brand-plate">
            <img
              src={asset('axiom-logo.jpg')}
              alt="Axiom"
              width={900}
              height={317}
              fetchPriority="high"
            />
          </span>

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
            <span className="hero__meta">
              v{VERSION} · MIT · six supported targets
            </span>
          </div>
        </div>

        <div className="hero__panel">
          <Code code={HERO.code} name="shapes.ax" badge="axiom run shapes.ax" />
          <div className="hero__out" role="group" aria-label="Program output">
            <span className="hero__out-label">stdout</span>
            <pre>{HERO.result}</pre>
          </div>
        </div>
      </div>
    </section>
  )
}
