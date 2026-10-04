# The Axiom standard-library reference

Choose a module by what you want to do. These recipes use public APIs;
the [generated API](stdlib-api.md) lists every signature and effect.
Import `Err` when working with `Result`, and use `try` to propagate errors.

| Task | Modules |
|---|---|
| strings and collections | [Str, Utf8, Vec, Map](#strings-and-collections), [Intern](#intern) |
| files and paths | [IO, Path, Sys](#io-path-and-sys) |
| failures and arithmetic | [Err, Fallible](#err-and-fallible) |
| numbers and formatting | [Fmt, Float, Pre](#fmt-float-and-pre) |
| TCP connections | [Net](#net) |
| structured data and messages | [Json](#json), [Rpc](#rpc) |
| dates and durations | [Chrono](#chrono) |
| databases | [Axqlite](#axqlite) |
| cryptography and embedded assets | [Crypto](#crypto) |
| concurrency | [Task, Par, Chan, Sync](#task-par-chan-and-sync) |
| terminals, testing and tooling | [Tui, Test, Agent.Tags](#terminals-tests-and-tools) |
| low-level interfaces | [Mem, Ffi](#mem-and-ffi) |

## Strings and collections

`Str` works on bytes. Join with `concat`, take a byte range with
`strSlice`, split with `strSplit`, and compare contents with `strEq` or
`strCmp`. `Utf8` supplies code-point access and display width.

`Vec` is a growable `(Vec a)`. `vecGet` traps on an invalid index;
`vecTry` returns an `Option`. `Map` uses integer keys and word values;
`mapGet` takes a fallback for an absent key.

```scheme
(import IO)
(import Str)
(import Vec)
(import Map)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((counts mapNew))
    {
      (for word in (strSplit "one two three" 32)
        (let ((n (strLen word)))
          (mapInsert counts n (+ (mapGet counts n 0) 1))))
      (for n in (vecSort (mapKeys counts))
        (let ((count (mapGet counts n 0)))
          (println "{n}: {count}")))
      0
    }))
```

```text
3: 2
5: 1
```

Use `vecNewRef` or `mapNewRefVals` when the container must retain
reference elements. See the [memory rules](memory-model.md) for
ownership, cycles and region resets.

API: [Str](stdlib-api.md#str), [Utf8](stdlib-api.md#utf8),
[Vec](stdlib-api.md#vec), [Map](stdlib-api.md#map).

## IO, Path and Sys

`IO` provides `println`, `eprintln`, descriptor reads and writes,
and files/directories by path. `Path` manipulates path strings without
I/O. `Sys` exposes descriptors, processes, the clock and readiness calls.

```scheme
(import IO)
(import Err)

(:: main (Result Int Error))
;@axiom:effect(io)
(fn (main)
  (try _ (writeFile "note.txt" "hello\n")
    {
      (println (readFile "note.txt"))
      (try _ (removeFile "note.txt") (Ok 0))
    }))
```

Most operations return `Result`. `readFile` and `listDir` return an
empty value on failure; use owned-file operations when you need a
reported read error. `openPath` returns a `File` that closes at its last
owner. `fileClose` closes early and reports the result.

API: [IO](stdlib-api.md#io), [Path](stdlib-api.md#path),
[Sys](stdlib-api.md#sys). Platform-specific files supply the target ABI.

## Err and Fallible

`Result a Error` is `Ok a` or `Err Error`. `(try x operation body)`
binds a successful value and evaluates `body`, or returns the failure.
Use `withContext` to add context and `errorText` to render it.

`mapOk`, `mapErr` and `andThen` compose results. `unwrapOr` supplies a
fallback. `okOr` converts absence to failure; `toOption` drops the
error. `Option` uses `Some` and `None` with `optMap` and `optUnwrapOr`.

Checked arithmetic includes `addChecked`, `subChecked`, `mulChecked`,
`divChecked`, `remChecked`, `shlChecked` and `shrChecked`.
`Fallible` handles malformed records in a batch: skip, substitute or
count them while continuing.

API: [Err](stdlib-api.md#err), [Fallible](stdlib-api.md#fallible).
The [error model](error-model.md) defines propagation and recovery.

## Fmt, Float and Pre

`format`, `println` and `eprintln` select rendering from static types.
Use `fmtInt`, `fmtHex`, `fmtFloatPrec` and padding functions when you
want to call a formatter directly. `Float` supplies strict parsing,
round-tripping text and bit conversions.

`Pre` supplies `when`, `unless`, `deriveEq` and `deriveArity`. Import
it before expanding those macros.

API: [Fmt](stdlib-api.md#fmt), [Float](stdlib-api.md#float),
[Pre](stdlib-api.md#pre). See [formatting syntax](reference.md#printing-and-formatting).

## Net

`Net.ax` provides numeric IPv4/IPv6 addresses, TCP listeners and TCP
streams. Streams block by default. This example creates both ends of
a loopback connection, sends bytes and reads until the sender shuts
its write half:

```scheme
(import IO)
(import Err)
(import Net)

(:: main (Result Int Error))
;@axiom:effect(io)
(fn (main)
  (try addr (socketAddrParse "127.0.0.1:0")
    (try listener (tcpListen addr)
      (try bound (tcpListenerAddr listener)
        (try client (tcpConnect bound)
          (try server (tcpAccept listener)
            (try _ (tcpWrite client "ping")
              (try _ (tcpShutdown client shutWrite)
                (try message (tcpReadAll server)
                  { (println message) (Ok 0) })))))))))
```

```text
ping
```

Port 0 lets the kernel choose an available port. `tcpListenerAddr`
returns that address. Listeners and streams are sealed counted owners;
the last share closes the descriptor. `tcpClose` and
`tcpListenerClose` close early and report errors. Using a closed owner
traps with status 85. These owners cannot be captured by `parallel`.

| Task | API |
|---|---|
| address | `socketAddrParse`, `socketAddrV4`, `socketAddrV6`; inspect with `socketAddrText`, `socketAddrIp`, `socketAddrPort`, `socketAddrIsV6` |
| serve | `tcpListen`, `tcpAccept`, `tcpListenerAddr`, `tcpListenerClose` |
| connect | `tcpConnect`, `tcpPeerAddr`, `tcpLocalAddr` |
| receive | `tcpRead` into a buffer, `tcpReadSome` for up to a limit, `tcpReadAll` until EOF |
| send | `tcpWrite` writes all bytes or returns an error |
| finish | `tcpShutdown` with `shutRead`, `shutWrite` or `shutBoth`; `tcpClose` |
| configure | `tcpSetNoDelay`, `tcpSetReadTimeout`, `tcpSetWriteTimeout`, `tcpSetNonBlocking` |
| poll | `tcpStreamFd` or `tcpListenerFd` with `Sys` readiness operations |

TCP is a byte stream: a read can return fewer bytes than requested.
Zero bytes from `tcpRead`, or an empty `tcpReadSome`, means EOF.
`tcpReadAll` waits for EOF, so establish a framing or shutdown convention.
A write to a closed peer returns an error instead of raising SIGPIPE.

Timeouts are in microseconds; 0 waits indefinitely. Non-blocking reads
and writes can return a would-block error. `Sys.netWouldBlock` recognises a negative raw error;
for a Net `Err e`, pass `(- 0 (errCode e))`.
Descriptors returned for polling remain owned by their stream/listener;
close the owner rather than the raw descriptor.

Addresses are numeric: `127.0.0.1:80` or `[::1]:80`. DNS, UDP, HTTP and
TLS require other libraries. See the [Net API](stdlib-api.md#net) for
all signatures and error behaviour.

Tested by `tests/stdlib/699-net-lifetime.ax` and `tests/stdlib/651-net-closed.ax`.

## Json

`jsonParse` returns a value handle, or 0 for invalid input; `jsonWrite`
serialises a value.
JSON numbers retain their spelling as strings, including large integers
and exponents. Objects preserve repeated keys; `jsonGet` returns the first.

```scheme
(import IO)
(import Json)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((value (jsonParse "{\"count\":1e3}")))
    (if (== value 0)
      { (eprintln "invalid JSON") 1 }
      { (println (jsonWrite value)) 0 })))
```

Use `jsonGet`, `jsonGetStr`, `jsonGetInt` and the array accessors to
inspect values. `jsonGet` returns 0 for an absent member; an explicit
JSON null has a non-zero handle. `jsonGetInt` and `jsonGetStr` return 0 and an empty string
for missing/wrong-kind values, so test the handle when absence matters.

`jsonNumText` preserves a number's full spelling. `jsonInt` reads its
signed leading digits: `1e3` gives 1 and `12.5` gives 12. Integer
overflow wraps; there is no floating-point accessor.

Build values with `jsonObj`, `jsonArr` and the scalar constructors.
`jsonObjPut` appends a member, including a repeated key; `jsonArrPush`
appends an element. `jsonBool` takes an integer: 0 is false.

Parsing rejects malformed numbers, trailing data and nesting beyond
the depth budget of 64. A failure has no location information.
Values use arena storage without individual release; `jsonWrite`
replaces malformed UTF-8 bytes with U+FFFD.

API: [Json](stdlib-api.md#json). Tested by `tests/stdlib/340-json.ax`.

## Rpc

`Rpc` reads and writes `Content-Length` framed messages over a descriptor.
Create a reader with `rdNew`, read with `rpcReadMsg`, and send with
`rpcWrite`. Decode the body separately with `Json`.

Keep one reader per stream: it retains unread bytes across fragmented
reads and consecutive frames. `rpcReadMsg` returns `Some` for every
complete frame, including an empty one. It returns `None` on EOF, a read
failure or invalid framing; `rpcRead` answers an empty string in those
cases and for an empty frame. Missing, invalid or oversized lengths
are refused; the body limit is 64 MiB.

Returned bodies are copied, so later reads preserve them. Reader-buffer
views may change during compaction. If you reclaim storage between
messages, `rdReseat` requires a live reader and a live unread byte range.

`rpcWrite` returns the body length even if a write fails. When you need
to detect that failure, construct the frame and check `IO.writeStr`'s
result for a negative raw error.

API: [Rpc](stdlib-api.md#rpc). Tested by `tests/stdlib/390-rpc-framing.ax`.

## Intern

`Intern` assigns dense integer IDs to distinct string contents. Create
with `internNew`, insert with `internIntern`, look up without inserting
with `internFind`, and recover bytes with `internLookup`.

<!-- doc-gate:run -->
```scheme
(import IO)
(import Intern)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (let ((names internNew)
        (id (internIntern names "compile")))
    {
      (println id)
      (println (internLookup names id))
      (internFree names)
      0
    }))
```

```text
0
compile
```

The table retains string handles without copying their bytes. Keep
the bytes alive and unchanged; intern `(strDup s)` when the source
buffer may change. IDs are stable within one interner; entries cannot
be removed. `internWithCapacity` reserves room for a known string count.

An invalid `internLookup` ID gives an empty string, which can also be
a valid value. Check against `internCount` when validity matters.
`internFree` requires an Unsafe boundary: release only a share you own,
and stop using the raw handle or unretained views after its last release.

API: [Intern](stdlib-api.md#intern). Tested by `tests/stdlib/090-intern.ax`.

## Chrono

`Chrono` supplies dates, times, naive date-times and durations. Parsing
and arithmetic return `Result` on invalid or out-of-range values.
`datetimeParseUtc` reads an offset-bearing timestamp and normalises it
to UTC; the resulting date-time has no offset field.

See the [date/time guide](chrono.md) for calendar arithmetic, strict
parsing and formatting. API: [Chrono](stdlib-api.md#chrono).

## Axqlite

Open with `axqOpen`; execute text with `axqExec`. Prepare a statement
with `axqPrepare` and bind values through `axqRun`, `axqQuery` or
`axqQueryEach`. Transactions use `axqBegin`, `axqCommit` and
`axqRollback`, or `axqTransaction`. Owners close/finalise automatically.

Start with the [database guide](axqlite.md). The [AXQL reference](axql.md)
defines queries and statement macros; [storage format](axqlite-format.md)
is for database implementers. API: [Axqlite](stdlib-api.md#axqlite).

## Crypto

Choose a high-level operation: hashes, HMAC, HKDF, authenticated
ChaCha20-Poly1305/AES-GCM encryption, X25519 key agreement or Ed25519
signatures. Keep keys in sealed `SecretBytes` owners and wipe them when
finished. Secure randomness returns an error if the target has no source.

[Cryptography](crypto.md) covers keys, nonces and the supported algorithms.
[Obfuscation](obfuscation.md) covers optional compiler obfuscation and
`Crypto.Obfuscate` authenticated asset packing. Embedded keys and decoded
bytes remain recoverable during runtime inspection.

API: [Crypto modules](stdlib-api.md#cryptosecret).

## Task, Par, Chan and Sync

`Task.taskMap` runs bounded `(-> Int String)` workers and returns ordered
`Result` values. `taskMapWith` adds deadlines, cancellation and fail-fast
options. `taskFold` consumes results with a scalar accumulator instead
of retaining a results vector.

`Par` runs word workers or external commands. `Chan` passes words
through a bounded channel; `Sync` provides mutexes with timeout and
owner-death reporting. Use shared handles through their module's public
operations. These APIs do not transfer arbitrary heap graphs between
processes or make unsynchronised payload mutation safe.

Read [concurrency](reference.md#concurrency) for capture and result rules.
API: [Task](stdlib-api.md#task), [Par](stdlib-api.md#par),
[Chan](stdlib-api.md#chan), [Sync](stdlib-api.md#sync).

## Terminals, tests and tools

`Tui.Keys`, `Tui.Edit` and `Tui.Term` decode keys, maintain editing state
and connect it to terminal I/O. `Test` provides labelled assertions for
`axiom test`. `Agent.Tags` reads AXSYM declarations, effects and tags.

See [testing](reference.md#testing), [editor setup](lsp.md) and
[symbol metadata](diagnostics.md#read-symbol-tags). Their signatures are in the
[generated API](stdlib-api.md).

## Mem and Ffi

`Mem` exposes raw allocation and byte/word access. Callers must establish
validity, bounds, alignment and lifetime behind an Unsafe boundary.
Prefer typed owners and containers for application code.

`Ffi` supports generated Rust wrappers: handles, result out-cells and
byte/vector conversion. Start at the [Rust FFI guide](ffi.md), then use
the generated operations for each sealed owner.

API: [Mem](stdlib-api.md#mem), [Ffi](stdlib-api.md#ffi).
