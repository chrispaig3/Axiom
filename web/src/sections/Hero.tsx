import { INSTALL_CMD, RELEASES, VERSION } from '../data/site.ts'
import { Command } from '../components/Command.tsx'
import { Demo } from '../components/Demo.tsx'
import { ArrowRight } from '../components/Icons.tsx'

/** "AXIOM" in figlet's ANSI Shadow face. Decoration: the h1 says the name. */
const BANNER = [
  ' █████╗ ██╗  ██╗██╗ ██████╗ ███╗   ███╗',
  '██╔══██╗╚██╗██╔╝██║██╔═══██╗████╗ ████║',
  '███████║ ╚███╔╝ ██║██║   ██║██╔████╔██║',
  '██╔══██║ ██╔██╗ ██║██║   ██║██║╚██╔╝██║',
  '██║  ██║██╔╝ ██╗██║╚██████╔╝██║ ╚═╝ ██║',
  '╚═╝  ╚═╝╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝     ╚═╝',
].join('\n')

export function Hero() {
  return (
    <section className="hero" id="top" aria-labelledby="hero-h">
      <div className="hero__bg" aria-hidden />
      <div className="container">
        <div className="hero__lead">
          <pre className="banner" aria-hidden>
            {BANNER}
          </pre>

          <p className="boot">
            <a href={`${RELEASES}/tag/v${VERSION}`} target="_blank" rel="noreferrer noopener">
              v{VERSION}
            </a>
            <span aria-hidden>·</span>
            <span>MIT</span>
            <span aria-hidden>·</span>
            <span className="boot__ready">READY.</span>
          </p>

          <h1 id="hero-h">
            Functional programming that ships{' '}
            <span className="grad">a binary, not a runtime.</span>
            <span className="cursor" aria-hidden />
          </h1>

          <p className="hero__lede">
            Algebraic data types, exhaustive matching and effects the compiler checks. Compiled
            through LLVM to a native executable with no VM, no garbage collector and no C library
            calls.
          </p>

          <div className="hero__actions">
            <a className="btn btn--primary btn--lg" href="#start">
              Get started
              <ArrowRight />
            </a>
            <a className="btn btn--ghost btn--lg" href="#tour">
              Take the tour
            </a>
          </div>
        </div>

        <div className="hero__stage">
          <Demo />
        </div>

        <div className="hero__install">
          <Command command={INSTALL_CMD} />
          <p className="hero__note">
            Prebuilt for macOS and Linux on arm64. Everywhere else,{' '}
            <a href="#start">build from source</a> with <code>llc</code> and a C compiler.
          </p>
        </div>
      </div>
    </section>
  )
}
