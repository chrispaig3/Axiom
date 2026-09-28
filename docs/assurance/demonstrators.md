# Demonstrators

These are the six working programs the assurance programme asked for.
Each row names the program and the gate that builds and runs it. A
demonstrator that no gate runs has already started to rot, so every
built one has a gate. A row whose evidence comes from an emulator says
so.

| # | Demonstrates | Program | Gate | Evidence |
|---|---|---|---|---|
| D-1 | A long-running service with bounded retained memory | `tests/net/echo-server.ax`: each request is handled in an arena scope (`MM-ALLOC-22`). The cache, aggregate and batch workloads of `scripts/check-steady-state.sh` turn a live set over completely with no reset | `scripts/check-net.sh`: 10,000 connections all echoed, with peak worker RSS at 384 KiB, beside an unscoped control that must grow. `scripts/check-steady-state.sh`: RSS flat across a tenfold rise in iterations, with the eviction removed as the control | Hosted, H1 to H3 |
| D-2 | Typed parallel processing with safe data transfer | [`examples/concurrency/typed-tasks.ax`](../../examples/concurrency/typed-tasks.ax): each task encodes a `struct` holding a `Vec` as JSON, and the parent decodes it and compares it with the sequential answer | `scripts/check-task.sh` §7, in both lowerings | Hosted, H1 to H3 |
| D-3 | Bounded producer/consumer concurrency | [`examples/concurrency/pipeline.ax`](../../examples/concurrency/pipeline.ax): three stages joined by two four-word channels, with timed receives through a stall | `scripts/check-task.sh` §7, in both lowerings; `scripts/check-chan.sh` for the channel under a 3×3 load | Hosted, H1 to H3 |
| D-4 | Cancellation and failure during active work | [`examples/concurrency/cancel.ax`](../../examples/concurrency/cancel.ax): a sharded search where one shard fails, one ignores the token and is killed after the grace, and the finder cancels the pool | `scripts/check-task.sh` §7, in both lowerings, which also requires no shard process to survive | Hosted, H1 to H3 |
| D-5 | An embedded periodic workload with explicit resource budgets | Open (R-D2c). The pieces exist: `tests/profile/ok-periodic.ax` passes the restricted profile with a stack bound of 192 bytes, and `tests/embedded/blink.ax` boots under QEMU. No program yet drives a periodic step from the timer interrupt | `scripts/check-report.sh` for the profile and the bound; `scripts/check-embedded.sh` A10 for the boot | QEMU TCG, which is an emulator, not hardware |
| D-6 | A driver with interrupt and DMA ownership boundaries | Open (R-D2c). The device primitives (`MM-FFI-8`), `isr(irq)` and the fault vector table exist, and no program yet combines them into a driver | `scripts/check-embedded.sh` A11 and A12 for the pieces | Compile-time and QEMU TCG |
