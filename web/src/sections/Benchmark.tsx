import { BENCH, BENCH_CMDS, BENCH_ENV } from '../data/bench.ts'
import { BLOB } from '../data/site.ts'
import { Code } from '../components/Code.tsx'

export function Benchmark() {
  return (
    <section className="section" id="speed" aria-labelledby="speed-h">
      <div className="container">
        <div className="lede-block">
          <span className="index">03</span>
          <h2 id="speed-h">
            Same loop. Same machine. Same speed.
          </h2>
          <p>
            Axiom lowers to LLVM IR and hands it to <code>llc</code>, which is
            the backend Rust and clang use. On work that is just arithmetic and
            branches, that means the machine code is the machine code — and the
            measurement says so.
          </p>
        </div>

        <div className="bench">
          <div className="bench__table" tabIndex={0} role="group" aria-label="Benchmark results, scrollable">
          <table>
            <caption className="visually-hidden">
              Run time, compile time, binary size and undefined symbol count
              for the same Collatz workload in Axiom, Rust and C.
            </caption>
            <thead>
              <tr>
                <th scope="col">Measurement</th>
                <th scope="col" className="bench__ax">
                  Axiom
                </th>
                <th scope="col">Rust</th>
                <th scope="col">C</th>
              </tr>
            </thead>
            <tbody>
              {BENCH.map((r) => (
                <tr key={r.metric}>
                  <th scope="row">
                    {r.metric}
                    <span>{r.how}</span>
                  </th>
                  <td className="bench__ax">{r.axiom}</td>
                  <td>{r.rust}</td>
                  <td>{r.c}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>

          <ol className="bench__notes">
            {BENCH.map((r) => (
              <li key={r.metric}>
                <span>{r.metric}</span>
                {r.note}
              </li>
            ))}
          </ol>
        </div>

        <div className="bench__method">
          <div>
            <h3>How it was measured</h3>
            <p>
              Collatz step counts for 1..3,000,000, summed and printed. Signed
              64-bit integers, no allocation, no library call in the hot loop.
              All three binaries print <code>{BENCH_ENV.answer}</code>. Each
              figure is the <strong>best</strong> of its runs, not the mean:
              interference only ever makes a run slower, so the minimum is the
              closest estimate of the cost itself — the methodology the
              repository uses for its own benchmarks.
            </p>
            <p>
              The runs are also <strong>interleaved</strong> — one repetition of
              each binary, in turn — and that correction changed the answer. A
              first pass that ran each binary in a block put Axiom 1.6&times;
              behind Rust, which would have been a finding if it were real. It
              was an artefact: a background build starting midway through taxes
              whichever block it lands on. Alternating gives every binary the
              same interference, and the three collapse onto each other.
            </p>
            <p>
              The three programs are in the repository —{' '}
              <a href={`${BLOB}/web/bench`}>
                <code>web/bench/</code>
              </a>{' '}
              — and <code>run-bench.sh</code> beside them produces every cell
              of this table, so it can be re-run rather than taken on trust.
            </p>
            <p className="micro">
              {BENCH_ENV.machine} · {BENCH_ENV.axiom} · {BENCH_ENV.rust} ·{' '}
              {BENCH_ENV.c}. Go and Haskell are absent on purpose: no toolchain
              for either was on the machine, and this project does not publish a
              number it has not measured. One micro-benchmark is one
              micro-benchmark — it says nothing about allocation-heavy work,
              which{' '}
              <a href={`${BLOB}/scripts/bench-datastructures.sh`}>
                <code>scripts/bench-datastructures.sh</code>
              </a>{' '}
              measures separately, and less flatteringly.
            </p>
          </div>
          <Code
            code={BENCH_CMDS}
            name="the three commands"
            axiom={false}
            wrap
          />
        </div>
      </div>
    </section>
  )
}
