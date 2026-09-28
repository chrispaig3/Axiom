import { STATUS_LIMITS, STATUS_REMOVED, STATUS_SOLID, type StatusRow } from '../data/content.ts'
import { DOCS } from '../data/site.ts'
import { SectionHead } from '../components/SectionHead.tsx'
import { ArrowUpRight } from '../components/Icons.tsx'
import { inline } from '../lib/inline.tsx'

/**
 * An honest summary of `docs/status.md`. Every row's feature name and
 * status word are that table's, exactly, and `check-claims.mjs` fails
 * the build when one is not - so this panel cannot promote a feature
 * the status table has not.
 */
function Column({ title, tone, rows }: { title: string; tone: string; rows: StatusRow[] }) {
  return (
    <div className="status__col" data-tone={tone}>
      <h3>{title}</h3>
      <ul>
        {rows.map((r) => (
          <li key={r.feature}>
            <span className="status__top">
              <b>{inline(r.feature)}</b>
              <span className="status__word">{r.status}</span>
            </span>
            <span className="status__note">{inline(r.note)}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

export function Status() {
  return (
    <section className="section" id="status" aria-labelledby="status-h">
      <div className="container">
        <SectionHead id="status-h" eyebrow="Status" title="Know what’s ready. See what’s next.">
          <p>
            Axiom is <code>0.x</code>: ready to explore, still evolving. Start with a tool, an experiment,
            or a contribution. Use this status map to decide where it fits; these rows reflect
            the project’s tested implementation status.
          </p>
        </SectionHead>

        <div className="status">
          <Column title="Complete" tone="ok" rows={STATUS_SOLID} />
          <Column title="Working, with stated limits" tone="warn" rows={STATUS_LIMITS} />
          <Column title="Removed on purpose" tone="muted" rows={STATUS_REMOVED} />
        </div>

        <p className="aside">
          Not here yet: a package index and version pinning, async and a scheduler, a compiler that
          runs on Windows (it builds Windows executables from elsewhere), and prebuilt archives
          beyond arm64.{' '}
          <a href={`${DOCS}/status.md`} target="_blank" rel="noreferrer noopener">
            The full table <ArrowUpRight size={12} />
          </a>
        </p>
      </div>
    </section>
  )
}
