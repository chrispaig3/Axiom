#!/usr/bin/env bash
# Typed optional lookups across the compiler.
#
# Each probe builds a small program with the compiler under test,
# in its own temporary directory, and checks that answer along
# with its negative controls. A mutation is an overlay the probe
# points `AXIOM_PATH` at, so the tree in this checkout stays as
# it was.
#
# One probe at a time, this list outlasts the hosted runner's
# six-hour job. A pool of two or three, chosen from the machine's
# memory, runs the same probes. `axiom run` keeps scratch names apart
# by pid, which `scripts/check-concurrent-run.sh` holds.
#
# Requires a compiler and the native toolchain.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"

gate_init
gate_build_axc axc

python3 - "$axc" << 'PY'
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

compiler = sys.argv[1]
probes = [
    ['tests/tools/compiler-representation.py', compiler],
    ['tests/selfhost/compiler-token-owners.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/compiler-parse-result-owners.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/emitter-context-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-flow-environment.py', '--axiom', compiler],
    ['tests/selfhost/emitter-index-owners.py', '--axiom', compiler],
    ['tests/selfhost/emitter-symbol-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-asm-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-pair-state.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-type-registry.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-edit-position-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-trivia-options.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-unsafe-site-options.py', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-nth-param-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-signature-diagnostic-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-contract-expr-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-match-arm-options.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-region-index-options.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-evidence-options.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-checked-type-options.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-optional-indices.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-bound-scope.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-lookup-options.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-result-options.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-region-records.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-compact-index.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-dup-link-guard.py', '--axiom', compiler],
    ['tests/selfhost/retained-constructor-child.py', '--axiom', compiler],
    ['tests/tools/format-option-specifiers.py', compiler],
    ['tests/selfhost/markdown-close-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/tools/formatter-structural-query-options.py', '--axiom', compiler],
    ['tests/tools/formatter-declaration-text-options.py', '--axiom', compiler],
    ['tests/tools/formatter-atom-text-options.py', '--axiom', compiler],
    ['tests/tools/formatter-flat-trial-options.py', '--axiom', compiler],
    ['tests/tools/expansion-option-frames.py', compiler],
    ['tests/tools/expansion-unit-lookup-options.py', '--axiom', compiler],
    ['tests/tools/expansion-option-bindings.py', compiler],
    ['tests/tools/checker-type-syntax-options.py', compiler],
    ['tests/tools/checker-effect-macro-options.py', compiler],
    ['tests/tools/checker-recursion-witness-options.py', compiler],
    ['tests/tools/checker-declaration-options.py', compiler],
    ['tests/tools/checker-current-signature-options.py', compiler],
    ['tests/tools/checker-alias-cycle-options.py', compiler],
    ['tests/tools/checker-for-help-options.py', compiler],
    ['tests/tools/checker-declared-result-options.py', compiler],
    ['tests/tools/checker-field-refusal-options.py', compiler],
    ['tests/tools/checker-effect-selection-options.py', compiler],
    ['tests/tools/checker-arrow-parameter-options.py', compiler],
    ['tests/tools/checker-declared-argument-options.py', compiler],
    ['tests/tools/checker-cast-source-options.py', compiler],
    ['tests/tools/symbol-map-options.py', compiler],
    ['tests/tools/checker-renderer-options.py', compiler],
    ['tests/selfhost/typecheck-show-outcomes.py', '--axiom', compiler],
    ['tests/tools/expander-asm-operand-index-options.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-module-queries.py', '--axiom', compiler],
    ['tests/tools/checker-syscall-effect-options.py', compiler],
    ['tests/tools/checker-field-initializer-options.py', compiler],
    ['tests/tools/checker-field-index-options.py', compiler],
    ['tests/tools/checker-type-variable-index-options.py', compiler],
    ['tests/tools/checker-parameter-index-options.py', compiler],
    ['tests/tools/checker-declared-arity-options.py', compiler],
    ['tests/tools/checker-function-arity-options.py', compiler],
    ['tests/tools/compiler-unit-name-options.py', '--axiom', compiler],
    ['tests/tools/expansion-option-sequences.py', compiler],
    ['tests/tools/expansion-option-queries.py', compiler],
    ['tests/tools/expansion-option-names.py', compiler],
    ['tests/tools/expansion-option-builders.py', compiler],
    ['tests/tools/expansion-option-controls.py', compiler],
    ['tests/tools/remaining-option-lookups.py', compiler],
    ['tests/tools/expansion-origin-options.py', compiler],
    ['tests/tools/macro-owning-records.py', compiler],
    ['tests/tools/macro-rule-index-options.py', compiler],
    ['tests/tools/expansion-canonical-module-options.py', '--axiom', compiler],
    ['tests/tools/symbol-map-index-options.py', compiler],
    ['tests/tools/symbol-axir-absence-options.py', '--axiom', compiler],
    ['tests/tools/axtag-owning-carriers.py', compiler],
    ['tests/tools/string-vector-option-queries.py', compiler],
    ['tests/tools/namespace-symbol-module-options.py', '--axiom', compiler],
    ['tests/selfhost/parser-type-parameter-owners.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/lsp-exact-parse-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/lsp-occurrence-value-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/lsp-declaration-query-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/lsp-cache-sync-import-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/lsp-workspace-read-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/lsp-doc-text-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/nolint-repl-absence-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/repl-load-result.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/emitter-type-metadata-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-temporary-return.py', '--axiom', compiler],
    ['tests/selfhost/parser-scan-options.py', '--axiom', compiler],
    ['tests/selfhost/parser-char-utf8-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/type-keyword-known.py', '--axiom', compiler],
    ['tests/tools/expansion-try-state-options.py', '--axiom', compiler],
    ['tests/selfhost/parser-typed-node-tag.py', '--axiom', compiler],
    ['tests/selfhost/diagnostic-option-fields.py', '--axiom', compiler],
    ['tests/selfhost/diagnostic-constructor-options.py', '--axiom', compiler],
    ['tests/selfhost/diagnostic-source-index.py', '--axiom', compiler],
    ['tests/selfhost/diagnostic-string-contracts.py', '--axiom', compiler],
    ['tests/selfhost/emitter-signature-types.py', '--axiom', compiler],
    ['tests/selfhost/emitter-lambda-type-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-signature-arity-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-data-field-query-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-alloca-marker-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-declaration-options.py', '--axiom', compiler],
    ['tests/selfhost/lsp-field-query-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/lsp-hierarchy-query-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/lsp-assist-query-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-entry-source-options.py', '--axiom', compiler],
    ['tests/selfhost/emitter-signature-flags.py', '--axiom', compiler],
    ['tests/selfhost/checker-axtag-owners.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/typecheck-axtag-presence.py', '--axiom', compiler],
    ['tests/selfhost/typecheck-axtag-delimiters.py', '--axiom', compiler],
    ['tests/tools/compiler-tag-consumers.py', '--axiom', compiler],
    ['tests/tools/expansion-interner-owner.py', compiler],
    ['tests/selfhost/doc-lookup-options.py', '--axiom', compiler],
    ['tests/selfhost/lsp-shape-result-options.py', '--axiom', compiler, '--negative-controls'],
    ['tests/selfhost/cli-flag-parts-options.py', '--axiom', compiler],
    ['tests/selfhost/fmt-option-value.py', '--axiom', compiler],
    ['tests/selfhost/cli-flag-values.py', '--axiom', compiler],
    ['tests/selfhost/lsp-type-result-options.py', '--axiom', compiler, '--negative-controls'],
]

page = os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES')
workers = 3 if page >= 12 * 1024 ** 3 else 2
lock = threading.Lock()
failed = []

def run(argv):
    started = time.monotonic()
    try:
        result = subprocess.run(
            [sys.executable, *argv],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=2700,
        )
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout or ''
        if isinstance(out, bytes):
            out = out.decode('utf-8', 'replace')
        return argv[0], 124, out, time.monotonic() - started
    return argv[0], result.returncode, result.stdout, time.monotonic() - started

with ThreadPoolExecutor(max_workers=workers) as pool:
    futures = [pool.submit(run, argv) for argv in probes]
    for future in as_completed(futures):
        name, rc, out, elapsed = future.result()
        with lock:
            if rc == 0:
                print(f'ok   {name} ({elapsed:.0f}s)', flush=True)
            else:
                failed.append(name)
                print(f'FAIL {name} exit {rc} after {elapsed:.0f}s', flush=True)
                tail = '\n'.join(out.splitlines()[-50:])
                if tail:
                    print(tail, flush=True)

print(f'{len(probes)} probes, {workers} at a time, {len(failed)} failed', flush=True)
sys.exit(1 if failed else 0)
PY

