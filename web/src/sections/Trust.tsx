import { BLOB, STATS } from '../data/site.ts'
import { BUILT } from '../data/content.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { ArrowUpRight, Check } from '../components/Icons.tsx'

/**
 * The fixpoint, drawn.
 *
 * `bootstrap/` holds the compiler's own LLVM IR, one file per target,
 * committed. The build runs `llc` and `cc` over the one matching the
 * host to get a seed, uses that to compile `self_host/` into a real
 * compiler, and then does it twice more, requiring the last two to be
 * byte-identical before it hands anything over.
 *
 * The caption under the brace is anchored at the diagram's right edge.
 * It was centred under the brace, and its last word ran past the
 * viewBox: the page read "refuses to hand you a binar".
 */
function Fixpoint() {
  const stops = [
    { label: 'bootstrap/*.ll', sub: 'committed IR' },
    { label: 'seed', sub: 'llc + cc' },
    { label: 'stage1', sub: 'built by the seed' },
    { label: 'stage2', sub: 'built by stage1' },
    { label: 'stage3', sub: 'built by stage2' },
  ]
  const last = stops.length - 1
  const W = 760
  const H = 150
  const pad = 10
  const step = (W - pad * 2) / last
  const y = 46
  const x = (i: number) => pad + i * step
  const anchor = (i: number) => (i === 0 ? 'start' : i === last ? 'end' : 'middle')

  return (
    <div className="fixpoint" tabIndex={0} role="group" aria-label="The bootstrap chain">
      <svg
        viewBox={`0 0 ${W} ${H}`}
        role="img"
        aria-label="The committed IR, run through llc and cc, produces a seed compiler; the seed compiles the compiler's source into stage 1, stage 1 into stage 2, stage 2 into stage 3; stage 2 and stage 3 must be byte-identical or the build hands over nothing."
      >
        {stops.slice(0, -1).map((_, i) => (
          <g key={i} className="fixpoint__arrow">
            <line x1={x(i) + 48} y1={y} x2={x(i + 1) - 52} y2={y} />
            <path d={`M${x(i + 1) - 52} ${y} l-6 -3.5 v7 z`} />
          </g>
        ))}
        {stops.map((s, i) => (
          <g key={s.label}>
            <circle
              className={i >= last - 1 ? 'fixpoint__dot fixpoint__dot--key' : 'fixpoint__dot'}
              cx={x(i)}
              cy={y}
              r={i >= last - 1 ? 6 : 4.5}
            />
            <text className="fixpoint__label" x={x(i)} y={y - 18} textAnchor={anchor(i)}>
              {s.label}
            </text>
            <text className="fixpoint__sub" x={x(i)} y={y + 24} textAnchor={anchor(i)}>
              {s.sub}
            </text>
          </g>
        ))}
        <path className="fixpoint__brace" d={`M${x(last - 1)} ${y + 40} v14 h${step} v-14`} />
        <text className="fixpoint__eq" x={W - pad} y={y + 76} textAnchor="end">
          must be byte-identical
        </text>
        <text className="fixpoint__sub" x={W - pad} y={y + 94} textAnchor="end">
          or the build hands you nothing
        </text>
      </svg>
      {/* The same chain, as a list, for a screen too narrow to draw it. */}
      <ol className="fixpoint__list">
        {stops.map((s, i) => (
          <li key={s.label} data-key={i >= last - 1 || undefined}>
            <code>{s.label}</code>
            <span>{s.sub}</span>
          </li>
        ))}
        <li className="fixpoint__verdict">stage2 and stage3 must be byte-identical, or the build hands you nothing</li>
      </ol>
    </div>
  )
}

const CHECKS = [
  {
    file: 'web/scripts/check-claims.mjs',
    what: 'Every number on this page is re-derived from the tree on each deploy: the line count, the file count, the diagnostic codes, the gates, the subcommands, the targets, and each row of the status panel. A stale figure fails the build rather than going live.',
  },
  {
    file: 'web/scripts/check-samples.mjs',
    what: 'Every program is compiled, formatted and run again, and must print exactly what the page shows. Every refusal must fail with exactly the report quoted beside it.',
  },
  {
    file: 'web/scripts/smoke.mjs',
    what: 'The page is rendered in Node and every link into the repository must name a file that exists and a heading that file has.',
  },
]

export function Trust() {
  return (
    <section className="section section--alt" id="trust" aria-labelledby="trust-h">
      <div className="container">
        <SectionHead id="trust-h" eyebrow="Proof, not promises" title="It compiles itself. This page checks itself.">
          <p>
            The compiler is written in Axiom, and the Rust implementation it replaced has been
            deleted. A clean checkout rebuilds it with nothing but <code>llc</code> and a C linker,
            and checks the fixpoint on the way, every time. The same rule governs this page: if it
            claims something, a script holds it.
          </p>
        </SectionHead>

        <div className="trust">
          <div className="trust__boot">
            <Fixpoint />
            <p className="trust__caption">
              <a href={`${BLOB}/scripts/bootstrap-from-seed.sh`} target="_blank" rel="noreferrer noopener">
                <code>scripts/bootstrap-from-seed.sh</code>
                <ArrowUpRight size={12} />
              </a>{' '}
              runs this chain with no network and no Rust, and refuses to install a compiler that did
              not reproduce itself.
            </p>
          </div>

          <ul className="trust__checks">
            {CHECKS.map((c) => (
              <li key={c.file}>
                <span className="trust__tick" aria-hidden>
                  <Check size={14} />
                </span>
                <div>
                  <a href={`${BLOB}/${c.file}`} target="_blank" rel="noreferrer noopener">
                    <code>{c.file}</code>
                  </a>
                  <p>{c.what}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <div className="built">
          <h3 className="built__title">Built with Axiom, and run by CI every day</h3>
          <ul className="built__grid">
            {BUILT.map((b) => (
              <li key={b.name}>
                <a href={`${BLOB}/${b.path}`} target="_blank" rel="noreferrer noopener">
                  <span className="built__name">
                    {b.name}
                    <ArrowUpRight size={12} />
                  </span>
                  <code className="built__path">{b.path}</code>
                  <span className="built__body">{b.body}</span>
                </a>
              </li>
            ))}
          </ul>
        </div>

        <dl className="ticker">
          {STATS.map((s) => (
            <div className="ticker__item" key={s.key}>
              <dt>
                <span className="ticker__n">{s.n}</span>
                <span className="ticker__l">{s.label}</span>
              </dt>
              <dd>
                <code>{s.evidence}</code>
              </dd>
            </div>
          ))}
        </dl>
      </div>
    </section>
  )
}
