import { useId, useState, type ReactNode } from 'react'
import {
  BOOTSTRAP_CMD,
  CLONE_CMD,
  DOCS,
  INSTALL_CMD,
  PATH_CMD,
  REPO,
  TARGETS,
} from '../data/site.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { Command } from '../components/Command.tsx'
import { CodeWindow, RunOutput } from '../components/Code.tsx'
import { ArrowUpRight, Check } from '../components/Icons.tsx'
import { NEW_PROJECT } from '../data/samples.ts'

/**
 * Getting started, in the order a newcomer does it.
 *
 * The prerequisite commands are the ones CI provisions with
 * (`.github/actions/provision/action.yml`); the installer is README's;
 * the project is what `axiom new` writes today, and its output was
 * captured from the compiler this page ships with.
 */

interface Tab {
  id: string
  label: string
  body: ReactNode
}

function Tabs({ tabs, label }: { tabs: Tab[]; label: string }) {
  const [active, setActive] = useState(0)
  const uid = useId()
  const current = tabs[active] ?? tabs[0]
  if (!current) return null

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return
    e.preventDefault()
    const next = (active + (e.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length
    setActive(next)
    document.getElementById(`${uid}-${next}`)?.focus()
  }

  return (
    <div className="ostabs">
      <div className="tabs tabs--pill" role="tablist" aria-label={label} onKeyDown={onKeyDown}>
        {tabs.map((t, i) => (
          <button
            key={t.id}
            id={`${uid}-${i}`}
            type="button"
            role="tab"
            className="tab"
            aria-selected={i === active}
            aria-controls={`${uid}-panel`}
            tabIndex={i === active ? 0 : -1}
            onClick={() => setActive(i)}
          >
            {t.label}
          </button>
        ))}
      </div>
      <div className="ostabs__panel" id={`${uid}-panel`} role="tabpanel" aria-labelledby={`${uid}-${active}`}>
        {current.body}
      </div>
    </div>
  )
}

const PREREQS: Tab[] = [
  {
    id: 'mac',
    label: 'macOS',
    body: (
      <>
        <Command command="xcode-select --install" />
        <Command command="brew install llvm" />
        <Command command={'export PATH="$(brew --prefix llvm)/bin:$PATH"'} />
        <p className="hint">
          The Command Line Tools supply the C compiler for the final link; Homebrew's LLVM supplies{' '}
          <code>llc</code>, which is not on the default path.
        </p>
      </>
    ),
  },
  {
    id: 'deb',
    label: 'Debian & Ubuntu',
    body: (
      <>
        <Command command="sudo apt-get install -y llvm clang" />
        <p className="hint">
          If <code>llc</code> is not found afterwards, add <code>$(llvm-config --bindir)</code> to
          your <code>PATH</code>.
        </p>
      </>
    ),
  },
  {
    id: 'other',
    label: 'Anything else',
    body: (
      <p className="hint">
        Any LLVM that provides <code>llc</code>, and any C compiler on the path as <code>cc</code>{' '}
        for the final link. That is the whole list: the compiler is written in Axiom, so there is no
        other toolchain to install first.
      </p>
    ),
  },
]

const INSTALLS: Tab[] = [
  {
    id: 'script',
    label: 'Installer',
    body: (
      <>
        <Command command={INSTALL_CMD} />
        <Command command={PATH_CMD} />
        <p className="hint">
          For macOS and Linux on arm64. It verifies the archive's SHA-256, then builds and runs a
          program that imports the standard library with the new compiler before it replaces
          anything, and it only ever replaces an installation it made itself.
        </p>
      </>
    ),
  },
  {
    id: 'source',
    label: 'From source',
    body: (
      <>
        <Command command={CLONE_CMD} />
        <Command command={BOOTSTRAP_CMD} />
        <Command command={'export PATH="$PWD/.axiom-bin:$PATH"'} />
        <p className="hint">
          Every supported host, including <code>linux-x86_64</code>. <code>bootstrap/</code> holds the
          compiler's own LLVM IR, so this needs nothing but the prerequisites, and no network after
          the clone.
        </p>
      </>
    ),
  },
]

export function Start() {
  return (
    <section className="section section--alt" id="start" aria-labelledby="start-h">
      <div className="container">
        <SectionHead id="start-h" eyebrow="Get started" title="From nothing to a native binary in three steps.">
          <p>
            You need <code>llc</code> from LLVM and a C compiler for the final link. That is the
            whole list.
          </p>
        </SectionHead>

        <ol className="steps">
          <li className="step">
            <div className="step__text">
              <h3>Install the two prerequisites</h3>
              <p>LLVM for code generation, and a C compiler to link.</p>
            </div>
            <Tabs tabs={PREREQS} label="Prerequisites by operating system" />
          </li>

          <li className="step">
            <div className="step__text">
              <h3>Install Axiom</h3>
              <p>A prebuilt archive where one exists, or the committed seed anywhere else.</p>
            </div>
            <Tabs tabs={INSTALLS} label="Ways to install" />
          </li>

          <li className="step">
            <div className="step__text">
              <h3>Start a project and run it</h3>
              <p>
                <code>axiom new</code> writes a program and an <code>axiom.pkg</code> manifest.
                Inside a project, <code>run</code> and <code>build</code> need no file name.
              </p>
            </div>
            <div className="step__demo">
              <Command command={`axiom new ${NEW_PROJECT.name} && cd ${NEW_PROJECT.name} && axiom run`} />
              <CodeWindow name={`${NEW_PROJECT.name}/Main.ax`} code={NEW_PROJECT.main} numbered={false}>
                <RunOutput command="axiom run" output={NEW_PROJECT.output} />
              </CodeWindow>
            </div>
          </li>
        </ol>

        <div className="next">
          <div className="next__col">
            <h3>Then, the commands you will use most</h3>
            <dl className="cheats">
              {[
                ['axiom check', 'type-check and verify every effect claim, no code generation'],
                ['axiom build', 'a native executable, named after the project'],
                ['axiom test', 'every function whose name starts with test'],
                ['axiom fmt', 'the one canonical layout'],
                ['axiom explain AX3005', 'the full explanation behind any diagnostic code'],
                ['axiom repl', 'an interactive session, compiled to native code line by line'],
              ].map(([c, d]) => (
                <div key={c}>
                  <dt>
                    <code>{c}</code>
                  </dt>
                  <dd>{d}</dd>
                </div>
              ))}
            </dl>
            <p className="hint">
              <a href={`${DOCS}/lsp.md`} target="_blank" rel="noreferrer noopener">
                Set up your editor <ArrowUpRight size={12} />
              </a>{' '}
              for highlighting, go-to-definition, hover and fixes.
            </p>
          </div>

          <div className="next__col">
            <h3>Where it runs</h3>
            <div className="table-wrap" tabIndex={0} role="group" aria-label="Supported targets">
              <table className="targets">
                <thead>
                  <tr>
                    <th scope="col">Target</th>
                    <th scope="col">Prebuilt</th>
                    <th scope="col">Notes</th>
                  </tr>
                </thead>
                <tbody>
                  {TARGETS.map((t) => (
                    <tr key={t.name}>
                      <th scope="row">
                        <code>{t.name}</code>
                      </th>
                      <td>
                        {t.archive ? (
                          <span className="yes">
                            <Check size={13} />
                            <span className="visually-hidden">yes</span>
                          </span>
                        ) : (
                          <span className="no">source</span>
                        )}
                      </td>
                      <td>{t.note}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="hint">
              <code>--target</code> emits for any of them from any host; only the final link needs
              that target's linker.{' '}
              <a href={`${REPO}#targets`} target="_blank" rel="noreferrer noopener">
                What "supported" means here
              </a>
              .
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}
