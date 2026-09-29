# Safety manual

This page is for an engineer deciding whether, and how, to use Axiom in
a system with safety or high-assurance requirements. It states what the
language and runtime guarantee, under which assumptions, what you must
do yourself, and what isn't provided at all.

Axiom isn't certified or qualified for any application. Whether it
suits a mission depends on the application, the hardware platform, the
configuration, the development process, and an independent assessment
this repository can't supply.

## Pick one configuration and freeze it

Use exactly one of the configurations in
[configurations.md](configurations.md), and freeze it: the target, the
`--opt` level, the runtime profile, and the versions of `opt`, `llc`,
`cc` and `ld.lld` you build with. Archive those with the build.
Evidence gathered here applies to the configuration it was observed on,
and to no other.

Execution evidence exists for linux-aarch64 and darwin-aarch64 in CI,
for freebsd-x86_64 and windows-x86_64 on narrower CI legs, and for
baremetal-aarch64 under QEMU only. linux-x86_64 is source-only: CI
builds the compiler there and runs no gates. No hardware
validation exists.

## The guarantee and its boundary

Take a program that type-checks, has no `;@axiom:effect(unsafe)`
declaration of its own, calls no `extern` item, and passes only live
handles where a library takes one as an `Int`. Such a program has no
cast that forges a reference and calls no precondition interface,
because each needs that tag (`AX3073`). `symbols` marks every tagged
declaration `#unsafe=` on a row that names its file, so the first
condition is one `grep`. The compiler and runtime keep it from:

- reading or writing outside a block through a container (`vecGet` and
  `vecSet` trap 77);
- using a block after it is reclaimed, through the region and reset
  rules (`MM-RGN-*`, traps 75 and 76);
- sharing a counted value or a container between threads (`AX3064`,
  R-C1);
- reading a failed join as success (78), or a failed task as an
  answer (`MM-PAR-13`).

Every rule, with its evidence, is in [requirements.md](requirements.md).
Every program obligation has a disposition in
[memory-audit.md](memory-audit.md).

Outside that boundary, correctness is your program's obligation: the
unsafe layer, `cast`, foreign code, words shared through `MAP_SHARED`
pages, and a handle freed while another binding still uses it. `scripts/axiom-report.py` and
[trusted-components.md](trusted-components.md) list where those uses
are.

Integer arithmetic wraps silently unless a body claims
`restrict(no-wrap)`, which is lexical: it refuses the operator and
points at `addChecked` and its siblings. A safety-relevant computation
should claim it.

## Rules for a restricted build

1. Run `python3 scripts/axiom-report.py --profile restricted --stack
   --stack-budget <bytes>` on every build, with the configuration's
   target and `--opt`, and treat a non-zero exit as a build failure
   ([restricted-profile.md](../restricted-profile.md)).
2. Tag every steady-state function, such as the periodic step and every
   handler, `;@axiom:restrict(no-alloc, no-recursion, strict)`. Tag
   interrupt entries `;@axiom:isr` or `;@axiom:isr(irq)`. Without
   `strict`, a claim the compiler can't settle is only a warning
   (`AX3051`).
3. Budget the heap with `--heap-ceiling`, and allocate only during
   initialisation. RP-5 checks the steady roots, not your intent.
4. Review every function the report lists as unsafe against the
   preconditions in `docs/memory-model.md`. For a dependency, that list
   is the dependency's trusted code.
5. Keep `--opt` fixed across verification and release. The
   `.optstable` evidence covers levels 0 to 3 for the runtime fixtures,
   not for your program.
6. Don't use `parallel`, the process pool, tasks, channels or the mutex
   in a restricted build (RP-4).

## Rules for a hosted concurrent build

- Guard every word more than one binding writes with `Sync`'s mutex,
  a `Chan` channel or the atomics (`MM-PAR-9` to `MM-PAR-11`).
- Where a wait could last for ever, use the timed form:
  `mutexLockTimeout`, `chanSendTimeout`, `chanRecvTimeout`, or a
  task deadline (`MM-PAR-12`, `MM-PAR-13`).
- Decide what a poisoned mutex means for your program. `syncOwnerDead`
  says its holder died holding it, and the data it guarded may be
  half-written.
- Give tasks a byte limit that fits their answers, and decode every
  answer as untrusted input.
- Supervise the process from outside. A process killed by `SIGKILL`
  runs no sweep, so its tasks are reparented and keep running. Under
  `--threads`, a trap in one thread doesn't sweep another thread's
  tasks.

## Failure behaviour, and what you must decide

A runtime check that fails traps. It writes one line to fd 2, or to
the UART on bare metal, prints a backtrace where one is available, and
exits with a defined status. A trap is not a safe state. The language
can't know what is safe for your system, so your system must map each
status to a response: restart, degrade, hold its outputs, or reset the
device.

| Status | Meaning |
|---|---|
| 70 | Out of memory, or a reference count at its limit |
| 71 | An operation performed with no handler in extent |
| 72 | Division by zero |
| 73 | FFI handle misuse (`ffiHandleClose`) |
| 74 | A syscall reached on a target with no syscall ABI, such as bare metal or Windows |
| 75, 76 | An arena reset to an invalid mark, or past a live handler |
| 77 | An index out of range |
| 78 | `parallel` couldn't spawn or join a binding |
| 79 | `parallel` on a target with no fork or threads |
| 80 | A violated `pre` or `post` contract |
| 81 | An unhandled CPU exception on `baremetal-aarch64` |
| 82 | An atomic whose address isn't 8-byte aligned |

The authoritative table, with the fixture that measures each status,
is in [memory-model.md](../memory-model.md). A trap inside a recovery
point (`MM-EXEC-10`) answers its status to the arming call instead of
exiting. That is how an application contains one. Status 81 can't be
recovered.

On baremetal-aarch64 the exit is a semihosting `SYS_EXIT`, which means
something under a debugger or QEMU. On hardware without a debugger the
`hlt` it uses is itself an exception, and the image goes no further.
Before stopping, an unhandled exception writes the vector offset and
`ESR_EL1`, `ELR_EL1` and `FAR_EL1` to the UART (`MM-EXEC-18`).

Supply your own fault policy with `;@axiom:isr(fault)`
(`MM-EXEC-19`). Every unrecovered trap and CPU exception reaches that
one function after its report, on its own stack with interrupts
masked, and its answer is the exit. On a board it should never return:
reset through the firmware, halt in a safe state, or stop feeding a
watchdog. What a synchronous fault means for your device is your
decision, and the embedded guide lists what the hook may and may not
do.

The port runs with the MMU on: code is read-only, data is
execute-never, and an unmapped 64 KiB guard sits below the stack. A
stack overflow is therefore a reported fault, not silent corruption,
but it still ends the program. Size the stack from the stack bound,
with a margin.

## What isn't provided

- No worst-case execution time analysis and no timing guarantee of any
  kind. Measured latencies are measurements.
- No multicore interference analysis of caches, bandwidth or shared
  devices ([tool-qualification.md](tool-qualification.md)).
- No protection against hardware faults such as bit flips, ECC errors
  or radiation upsets. Language memory safety doesn't address them.
  One boundary detects some: a single-bit fault in a live channel,
  mutex, token or spawn handle traps 85, unless the flip spells another
  live handle of the same kind (`scripts/check-handles.sh` §7). A flip
  anywhere else, in a `Vec`'s length, a count word or the object a
  handle names, isn't detected.
- No structural coverage measurement of your program. The compiler's
  own coverage is measured ([tool-qualification.md](tool-qualification.md)).
- No qualified tool, no certification, and no independent assessment.

## Known limitations and errata

The open defects and limitations, with their workarounds, are in
[anomalies.md](anomalies.md). The gaps for each guarantee are the Gaps
column of [requirements.md](requirements.md). Read both for the
version you use. [support-policy.md](support-policy.md) says which
versions receive fixes.
