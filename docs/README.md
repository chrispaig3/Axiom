# Read Axiom's docs

Start with a working program, then look up the language or library
feature you need. Detailed compiler contracts are linked separately.

## Start here

1. [Install and run your first program](../README.md#install).
2. [Learn the language](reference.md): functions, data, effects and modules.
3. [Choose a standard-library module](stdlib.md): collections, files, TCP, dates and more.
4. [Configure your editor](lsp.md), or [browse complete programs](../examples/README.md).

The [generated API](stdlib-api.md) is the complete public-name listing.
[What's ready today](status.md) records feature and target limits.

## Go further

| Work | Guide |
|---|---|
| link native code | [Rust FFI](ffi.md) |
| store/query data | [Axqlite](axqlite.md), [AXQL](axql.md) |
| dates and durations | [Chrono](chrono.md) |
| keys and encrypted data | [Crypto](crypto.md), [optional obfuscation](obfuscation.md) |
| embedded programs | [Embedded guide](embedded-guide.md), [restricted profile](restricted-profile.md) |
| compiler output and tooling | [Diagnostics](diagnostics.md), [inspection](compiler-guide.md), [agent harness](agent-harness.md) |
| migrate a program | [Compatibility](compatibility.md) |

## Compiler contracts and development

The [memory](memory-model.md), [error](error-model.md) and
[macro](macro-system.md) specifications define rules and their evidence.
[Contributing](../CONTRIBUTING.md) covers building, validation and releases.
The [assurance plan](assurance/plan.md) records engineering milestones,
verified configurations and qualification gaps.

Designs and proposals describe work under consideration; use the
language reference and feature status for implemented behaviour.
