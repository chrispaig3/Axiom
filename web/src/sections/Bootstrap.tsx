import { BLOB, STATS } from '../data/site.ts'

/**
 * The fixpoint, drawn.
 *
 * `bootstrap/` holds the compiler's own LLVM IR, one file per target,
 * committed. The build runs `llc` and `cc` over the one matching the
 * host to get a seed, uses that to compile `self_host/` into a real
 * compiler, and then does it twice more — requiring the last two to be
 * byte-identical before it hands anything over.
 *
 * (README.md, "Build the compiler from source".)
 */
function Fixpoint() {
  const stops = [
    { x: 0, label: 'bootstrap/*.ll', sub: 'committed IR' },
    { x: 1, label: 'seed', sub: 'llc + cc' },
    { x: 2, label: 'stage1', sub: 'built by the seed' },
    { x: 3, label: 'stage2', sub: 'built by stage1' },
    { x: 4, label: 'stage3', sub: 'built by stage2' },
  ]

  const last = stops.length - 1
  const W = 760
  const H = 148
  const pad = 8
  const step = (W - pad * 2) / last
  const y = 46

  return (
    <div className="fixpoint">
      <svg
        viewBox={`0 0 ${W} ${H}`}
        role="img"
        aria-label="bootstrap slash star dot l l, run through l l c and c c, produces a seed compiler; the seed compiles self_host into stage 1, stage 1 into stage 2, stage 2 into stage 3; stage 2 and stage 3 must be byte-identical."
      >
        {/* the chain */}
        {stops.slice(0, -1).map((s) => (
          <g key={s.x} className="fixpoint__arrow">
            <line
              x1={pad + s.x * step + 46}
              y1={y}
              x2={pad + (s.x + 1) * step - 50}
              y2={y}
            />
            <path
              d={`M${pad + (s.x + 1) * step - 50} ${y} l-6 -3.5 v7 z`}
              fill="currentColor"
              stroke="none"
            />
          </g>
        ))}

        {stops.map((s, i) => (
          <g key={s.label}>
            <circle
              className={i >= last - 1 ? 'fixpoint__dot fixpoint__dot--key' : 'fixpoint__dot'}
              cx={pad + s.x * step}
              cy={y}
              r={i >= last - 1 ? 6 : 4.5}
            />
            <text
              className="fixpoint__label"
              x={pad + s.x * step}
              y={y - 18}
              textAnchor={i === 0 ? 'start' : i === last ? 'end' : 'middle'}
            >
              {s.label}
            </text>
            <text
              className="fixpoint__sub"
              x={pad + s.x * step}
              y={y + 22}
              textAnchor={i === 0 ? 'start' : i === last ? 'end' : 'middle'}
            >
              {s.sub}
            </text>
          </g>
        ))}

        {/* the equality that gates the build */}
        <path
          className="fixpoint__brace"
          d={`M${pad + (last - 1) * step} ${y + 40} v14 h${step} v-14`}
        />
        <text
          className="fixpoint__eq"
          x={pad + (last - 0.5) * step}
          y={y + 74}
          textAnchor="middle"
        >
          must be byte-identical
        </text>
        <text
          className="fixpoint__sub"
          x={pad + (last - 0.5) * step}
          y={y + 92}
          textAnchor="middle"
        >
          or the build refuses to hand you a binary
        </text>
      </svg>
    </div>
  )
}

export function Bootstrap() {
  return (
    <section className="section band" id="why" aria-labelledby="boot-h">
      <div className="container">
        <div className="lede-block">
          <span className="index">01</span>
          <h2 id="boot-h">It compiles itself. Byte for byte, every time.</h2>
          <p>
            Not a rewrite in progress — the Rust implementation it replaced has
            been deleted. A clean checkout rebuilds the whole thing with nothing
            but <code>llc</code> and a C linker, and checks the fixpoint on the
            way, every time —{' '}
            <a
              href={`${BLOB}/scripts/bootstrap-from-seed.sh`}
              target="_blank"
              rel="noreferrer noopener"
            >
              scripts/bootstrap-from-seed.sh
            </a>
            .
          </p>
        </div>

        <div>
          <Fixpoint />
        </div>

        <div className="ticker">
          {STATS.map((s) => (
            <div className="ticker__item" key={s.label}>
              <span className="ticker__n">{s.n}</span>
              <span className="ticker__l">{s.label}</span>
              <span className="ticker__e">{s.evidence}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
