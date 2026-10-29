# The Axiom standard-library reference

Choose a module by what you want to do. These recipes use public APIs;
the [generated API](stdlib-api.md) lists every signature and effect.
Import `Err` when working with `Result`, and use `?` to propagate errors.

| Task | Modules |
|---|---|
| strings and collections | [Str, Utf8, Vec, Map](#strings-and-collections), [Intern](#intern) |
| files and paths | [IO, Path, Sys](#io-path-and-sys) |
| failures and arithmetic | [Err, Fallible](#err-and-fallible) |
| numbers and formatting | [Fmt, Float, Pre](#fmt-float-and-pre) |
| TCP connections | [Net](#net) |
| structured data and messages | [Cereal](#cereal), [Rpc](#rpc) |
| dates, durations, a monotonic clock and sleep | [Chrono](#chrono) |
| databases | [Axqlite](#axqlite) |
| cryptography and embedded assets | [Crypto](#crypto) |
| concurrency | [Task, Chan, Sync](#task-chan-and-sync) |
| terminals, testing and tooling | [Tui, Test, Agent.Tags](#terminals-tests-and-tools) |
| low-level interfaces | [Mem](#mem) |

## Strings and collections

`Str` works on bytes. Join two strings with `concat` and many with
`strJoin` or a `StrBuilder`. Take a byte range with `strSlice`, split
with `strSplit`, and compare contents with `strEq` or `strCmp`. `Utf8`
supplies code-point access and display width.

`Vec` is a growable `(Vec a)`. `vecGet` traps on an invalid index;
`vecTry` returns an `Option`. A `(Map v)` maps integer keys to values
of type `v`: `mapGet` answers a `v`, and takes a fallback of that type
for an absent key.

```scheme
(import IO)
(import Str)
(import Vec)
(import Map)

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let counts mapNew)
    {
      (for word in (strSplit "one two three" 32)
        {
          (let n (strLen word))
          (mapInsert counts n (+ (mapGet counts n 0) 1))
        })
      (for n in (vecSort (mapKeys counts))
        {
          (let count (mapGet counts n 0))
          (println "{n}: {count}")
        })
    }
  })
```

```text
3: 2
5: 1
```

A `Vec` or `Map` owns the strings, vectors and records you store in
it, and releases them when its last reference goes. See the
[memory rules](memory-model.md) for ownership, cycles and region
resets.

`concat` copies both of its strings, so appending with it in a loop
takes time that grows with the square of the result. To build a string
from many pieces, push them into a `StrBuilder` and finish it, or join
a `Vec` with `strJoin`. Both take time in proportion to the bytes
appended. The finished `String` keeps its bytes when the builder takes
more.

```scheme
(import IO)
(import Str)
(import Utf8)

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let b strBuilderNew)
    (for word in (strSplit "one two three" 32)
      {
        (strBuilderPush b word)
        (utf8PushChar b (as '→' Int))
      })
    (strBuilderPush b "done")
    (println (strBuilderFinish b))
    (println (strJoin (strSplit "one two three" 32) ", "))
  })
```

```text
one→two→three→done
one, two, three
```

Tested by `tests/stdlib/988-str-builder.ax` and
`tests/stdlib/990-str-builder-scale.ax`.

API: [Str](stdlib-api.md#str), [Utf8](stdlib-api.md#utf8),
[Vec](stdlib-api.md#vec), [Map](stdlib-api.md#map).

## IO, Path and Sys

`IO` holds every file your program opens: plain files, sockets and the
standard streams. Each is a `File`, an owner that closes its descriptor
when its last share goes. No function hands you the descriptor number
inside it, so nothing can close or reuse a descriptor behind its owner's
back. `Path` manipulates path strings without I/O, and `Sys` covers
processes, the environment, the clock and signals.

```scheme
(import IO)
(import Err)

(:: main (Result Int Error))
;@axiom:effect(io)
(fn (main)
  {
    (writeFile "note.txt" "hello\n")?
    {
      (let f (openPath "note.txt" oRdonly)?)
      (let text (readAll f)?)
      {
        (writeStr stdout text)
        (removeFile "note.txt")?
        (Ok 0)
      }
    }
  })
```

```text
hello
```

`stdin`, `stdout` and `stderr` are `File` values too, and they never
close the process's streams. `println` and `eprintln` write through
`writeOut` and `writeErr`, which make no `File`, so printing allocates
nothing. The other readers and writers take a `File`:

| Task | API |
|---|---|
| open and close | `openPath`, `fileClose` |
| read | `readLine`, `readAll`, and `fileRead` into a `ReadBuffer` you allocated with `readBufferNew` |
| write | `writeStr` and `writeSlice` answer a count or a negative errno; `fileWrite` answers a `Result`; `writeOut` and `writeErr` write to the standard streams |
| by path | `readFile`, `writeFile`, `appendFile`, `copyFile`, `removeFile`, `renamePath`, `fileExists`, `fileSize`, `isDir`, `listDir`, `makeDir`, `makeDirAll`, `removeDir`, `cwd` |
| wait on many | `pollerNew`, `pollerAdd`, `pollerRemove`, `pollerAddSignals`, `pollerWait`, `pollerToken`, `pollerSignal`, `pollerClose` |
| terminals | `isTerminal`, `termSize`, and `termRaw`, which answers a `TermGuard` |
| failures | `errorKind` names an `Error` the same way on every target, with Rust's `std::io::ErrorKind` names: `NotFound`, `WouldBlock`, `TimedOut` and the rest |

`fileClose` closes early and reports the result, and any later use of
that file stops the program with status 85. Closing a standard stream
retires that one value and leaves the stream open.

A `Poller` watches files and sockets under tokens you choose, and a
wait answers the tokens. It owns its kqueue or epoll descriptor, and
closes it when its last share goes. On Windows it keeps a table of its
registrations instead and waits with `WSAPoll`, over sockets only. Raw
mode is an owner too: releasing
the `TermGuard` that `termRaw` answers puts the terminal back as it
was, and `termRestore` does it early.

`readFile` and `listDir` answer a `Result`: `(readFile path)?` gives
you the text, or passes the error on. A missing file is ENOENT, a
directory given to `readFile` is EISDIR, and an empty file is
`(Ok "")`.

Tested by `tests/stdlib/785-stdio-file.ax` and
`tests/stdlib/786-poller-owned.ax`.

API: [IO](stdlib-api.md#io), [Path](stdlib-api.md#path),
[Sys](stdlib-api.md#sys). Platform-specific files supply the target ABI.

## Err and Fallible

`Result a Error` is `Ok a` or `Err Error`. `operation?` answers the
successful value, or returns the failure from the function you are in.
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
round-tripping text and bit conversions. `fmtFloatPrec` and
`floatToFixed` round the exact binary64 value, halfway cases away from
zero, across the full finite range. Negative precision means zero places;
precision above 4096 traps. Signed zero, infinities and NaN keep clear
spellings. Formatting scratch is reclaimed inside a lexical region; the
returned string owns storage outside it. Tested by
`tests/stdlib/949-fixed-width-alias-callback.ax`.

`Pre` supplies two derivers: `deriveEq` writes structural equality
for a type with nullary constructors, and `deriveArity` writes a
function answering how many fields a value's constructor carries.

API: [Fmt](stdlib-api.md#fmt), [Float](stdlib-api.md#float),
[Pre](stdlib-api.md#pre). See [formatting syntax](reference.md#printing-and-formatting).

## Net

Net gives you TCP the way Rust's `std::net` does: listeners, streams
and the IP addresses they open on. Libraries bring HTTP, TLS, name
lookup and UDP.

This server echoes each line a client sends until the client hangs up:

```scheme
(import IO)
(import Err)
(import Str)
(import Net)

(:: report (-> String Error Int))
;@axiom:effect(io)
(fn (report what e)
  {
    (let why (errorText e))
    (eprintln "{what}: {why}")
  })

; Echo each line back until the client hangs up.
(:: serve (-> TcpStream Int))
;@axiom:effect(io)
(fn (serve conn)
  (match (tcpReadLine conn 4096)
    ((Ok (Some line))
      (match (tcpWrite conn (concat line "\n"))
        ((Ok _) (serve conn))
        ((Err e) (report "write" e)))
    )
    ((Ok (None)) 0)
    ((Err e) (report "read" e))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (tcpListen "127.0.0.1:7878")
    ((Err e) (report "listen" e))
    ((Ok lsn)
      {
        (println "listening on 127.0.0.1:7878")
        (while true
          (match (tcpAccept lsn)
            ((Ok conn) (serve conn))
            ((Err e) (report "accept" e))))
        0
      }
    )))
```

`tcpListen` and `tcpConnect` take an address as text, and
`tcpListenAddr` and `tcpConnectAddr` take a `SocketAddr` you already
hold. Each accepted connection is a `TcpStream`. When `serve` returns,
the stream's last share goes and its socket closes. A failed accept or
connection is reported, and the server carries on with the next one.

That server handles one client at a time. The non-blocking server
further down handles many.

A client sends a line and waits up to a second for the reply:

```scheme
(import IO)
(import Err)
(import Str)
(import Net)

; Send one line and wait up to a second for the answer.
(:: ask (-> TcpStream String String))
;@axiom:effect(io)
(fn (ask conn question)
  (match (tcpWrite conn (concat question "\n"))
    ((Err e) (errorText e))
    ((Ok _)
      (match (tcpReadLine conn 4096)
        ((Ok (Some answer)) answer)
        ((Ok (None)) "the server hung up")
        ((Err e)
          (match (errorKind e)
            ((TimedOut) "no answer within a second")
            (_ (errorText e)))
        ))
    )))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (tcpConnect "127.0.0.1:7878")
    ((Err e)
      (match (errorKind e)
        ((ConnectionRefused)
          {
            (eprintln "nothing is listening on port 7878")
            1
          }
        )
        (_
          {
            (eprintln (errorText e))
            1
          }
        ))
    )
    ((Ok conn)
      {
        (let _ (tcpSetReadTimeout conn (Some 1000)))
        (let reply (ask conn "hello"))
        {
          (println reply)
          0
        }
      }
    )))
```

Run against the echo server, it prints:

```text
hello
```

Match on `errorKind` to tell failures apart: `ConnectionRefused` means
nothing is listening, and `TimedOut` means a timeout ran out. The
kinds are the names of Rust's `std::io::ErrorKind`, and they mean the
same on every target.

`tcpReadLine` answers one line without its `\n` or `\r\n`, and `None`
when the peer closes. Its second argument caps the line's length, so a
peer can't grow your memory without bound. `tcpReadExact` reads a
fixed-size frame, and `tcpReadSome`, `tcpRead` and `tcpReadAll` read
whatever arrives.

A non-blocking server waits on a `Poller` and serves whichever sockets
are ready:

```scheme
(import IO)
(import Err)
(import Str)
(import Vec)
(import Net)

; Echo every line `conn` has ready. False once the client has gone.
(:: drain (-> TcpStream Bool))
;@axiom:effect(io)
(fn (drain conn)
  (match (tcpReadLine conn 4096)
    ((Ok (Some line))
      (if (isOk (tcpWrite conn (concat line "\n")))
        (drain conn)
        false)
    )
    ((Ok (None)) false)
    ((Err e)
      (match (errorKind e)
        ((WouldBlock) true)
        (_ false))
    )))

; Accept every waiting client and watch it under its slot plus one.
(:: acceptAll (-> TcpListener Poller (Vec (Option TcpStream)) Int))
;@axiom:effect(io)
(fn (acceptAll lsn p conns)
  (match (tcpAccept lsn)
    ((Ok conn)
      {
        (let _ (tcpSetNonBlocking conn true))
        (let _ (pollerAddStream p conn (+ (vecLen conns) 1)))
        {
          (vecPush conns (Some conn))
          (acceptAll lsn p conns)
        }
      }
    )
    ((Err e)
      (match (errorKind e)
        ((WouldBlock) 0)
        (_
          {
            (let why (errorText e))
            (eprintln "accept: {why}")
          }
        ))
    )))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (tcpListen "127.0.0.1:7878")
    ((Err e)
      {
        (eprintln (errorText e))
        1
      }
    )
    ((Ok lsn)
      (match (pollerNew 64)
        ((Err e)
          {
            (eprintln (errorText e))
            1
          }
        )
        ((Ok p)
          {
            (let conns vecNew)
            (let _ (tcpListenerSetNonBlocking lsn true))
            (let _ (pollerAddListener p lsn 0))
            {
              (while true
                {
                  (let n (unwrapOr (pollerWait p -1) 0))
                  (for i in 0..n
                    {
                      (let token (pollerToken p i))
                      (if (== token 0)
                        (acceptAll lsn p conns)
                        (match (vecGet conns (- token 1))
                          ((Some conn)
                            (if (drain conn)
                              0
                              {
                                (vecSet conns (- token 1) None)
                                0
                              })
                          )
                          ((None) 0)))
                    })
                })
              0
            }
          }
        ))
    )))
```

A non-blocking read with nothing to answer fails with `WouldBlock`, so
`drain` reads until it does. That matters because `tcpReadLine` reads
ahead, and the bytes it holds wake no poller; `tcpBuffered` counts
them. Setting a slot to `None` drops the stream, which closes it and
removes it from the poller. This example never reuses a slot.

| Task | API |
|---|---|
| addresses | `ipV4`, `ipV6`, `ipParse`, `socketAddrNew` and `socketAddrParse` build them; `socketAddrIp`, `socketAddrPort`, `ipText` and `socketAddrText` read them; `ipIsLoopback`, `ipIsPrivate` and the other `ipIs` predicates test them |
| listen | `tcpListen`, `tcpListenAddr`, `tcpAccept`, `tcpListenerLocalAddr` |
| connect | `tcpConnect`, `tcpConnectAddr`, `tcpConnectTimeout`, `tcpPeerAddr`, `tcpLocalAddr` |
| read | `tcpReadLine`, `tcpReadExact`, `tcpReadSome`, `tcpRead` into a `ReadBuffer`, `tcpReadAll`, `tcpPeek`, `tcpBuffered` |
| write | `tcpWrite` writes everything; `tcpWriteSome` writes what fits and says how much |
| finish | `tcpShutdown` with `ShutdownRead`, `ShutdownWrite` or `ShutdownBoth`; `tcpClose` |
| configure | `tcpSetReadTimeout`, `tcpSetWriteTimeout`, `tcpSetNoDelay`, `tcpSetTtl` and `tcpSetNonBlocking`, with a getter for each but the last; `tcpTakeError` |
| poll | `pollerAddListener`, `pollerAddStream`, `tcpListenerSetNonBlocking` |

Timeouts are in milliseconds: `(Some 250)` sets one and `None` clears
it. `tcpShutdown` half-closes a connection. After `ShutdownWrite` the
peer reads end of stream, and you can still read its reply. A stream
closes itself when its last share goes, and `tcpClose` closes it early
and reports the result. Listeners and streams can't be captured by
`parallel`.

Tested by `tests/stdlib/699-net-lifetime.ax` and `tests/stdlib/651-net-closed.ax`.

Addresses are numeric, as in `127.0.0.1:80` or `[::1]:80`. `ipV4`
takes `Byte`s and `socketAddrNew` takes a `Port`, so an out-of-range
number stops the program with status 80. Text from outside your
program goes through `socketAddrParse`, which answers an error
instead. A write to a peer that has gone away answers `BrokenPipe`;
it never raises SIGPIPE.

See the [Net API](stdlib-api.md#net) for every signature.

Tested by `tests/stdlib/841-net-ip.ax` and `tests/stdlib/843-net-stream.ax`.

<a id="json"></a>
## Cereal

`Cereal` reads and writes JSON, TOML and YAML through one typed value,
`CerealValue`. Decode a document, read the fields you need with a
codec, and encode it again in any of the three formats.

<!-- doc-gate:run -->
```scheme
(import IO)
(import Err)
(import Cereal)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (cerealDecode CerealToml "name = \"axiom\"\nport = 8080\n")
    ((Err e)
      {
        (eprintln (errorText e))
        1
      }
    )
    ((Ok doc)
      (match (cerealField cerealIntCodec doc "port")
        ((Err e)
          {
            (eprintln (errorText e))
            1
          }
        )
        ((Ok port)
          (match (cerealEncode CerealJson doc)
            ((Err e)
              {
                (eprintln (errorText e))
                1
              }
            )
            ((Ok json)
              {
                (println "port {port}")
                (println json)
                0
              }
            ))
        ))
    )))
```

```text
port 8080
{"name":"axiom","port":8080}
```

A `CerealValue` is `CNull`, `CBool`, `CInt`, `CNumber` (a decimal kept
as its spelling), `CText`, `CArray` or `CObject`, whose members keep
their order. A `Codec a` converts your own type to and from that tree:
compose `cerealIntCodec`, `cerealTextCodec`, `cerealBoolCodec`,
`cerealVecCodec` and `cerealOptionCodec`, read members with
`cerealField`, and use `cerealSerialize` and `cerealDeserialize` to go
straight between a type and text. A missing or wrongly typed field is
an `Error` that names its path.

Every decode and encode is bounded by `CerealLimits`: nesting depth,
bytes and nodes. `cerealLimits` gives the defaults (depth 64, 1 MiB,
100,000 nodes); the `...With` forms take your own.

The `json*` functions are the older handle interface, kept for
JSON-RPC: `jsonParse` returns a handle or 0, `jsonGet` returns 0 for an
absent member, and `jsonGetInt` and `jsonGetStr` return 0 or an empty
string for a missing value. For a raw object, `jsonFind` returns `Some`
for a present member, including `null`. It returns `None` for an absent
member or a value that is not an object. Prefer `CerealValue` in new code.

API: [Cereal](stdlib-api.md#cereal). Tested by
`tests/stdlib/705-cereal.ax` and `tests/stdlib/706-cereal-yaml.ax`.

## Rpc

`Rpc` reads and writes `Content-Length` framed messages over a descriptor.
Create a reader with `rdNew`, read with `rpcRead`, and send with
`rpcWrite`. Decode the body separately with `Cereal`.

Keep one reader per stream: it retains unread bytes across fragmented
reads and consecutive frames. `rpcRead` returns `Some` for every
complete frame, including an empty one. It returns `None` on EOF, a read
failure or invalid framing. Missing, invalid or oversized lengths
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

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let names internNew)
    (let id (internIntern names "compile"))
    {
      (println id)
      (println (internLookup names id))
      (internFree names)
    }
  })
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

An `Instant` reads the monotonic clock, which never steps backwards:
`instantNow` and `instantElapsed` time your work. `sleepFor` and
`sleepUntil` block until at least that much time has passed. Tested by
`tests/stdlib/851-instant-sleep.ax`.

See the [date/time guide](chrono.md) for calendar arithmetic, strict
parsing, formatting and sleeping. API: [Chrono](stdlib-api.md#chrono).

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

<a id="task-par-chan-and-sync"></a>

## Task, Chan and Sync

`Task.taskMap` runs bounded `(-> Int String)` workers and returns ordered
`Result` values. `taskMapWith` adds deadlines, cancellation and fail-fast
options, and budgets: `taskWithKeep` for the answer bytes a call holds,
`taskWithMemory` for each task's memory, and `taskWithStack` for the
stack each task runs on, 8 MiB by default (`taskStackDefault`). A task
that recurses past its stack answers `Err` 86, "task out of stack",
while its siblings go on. The stack is the task's own, so it's the same
size wherever the pool started. Tested by
`tests/stdlib/852-task-budgets.ax` and `tests/stdlib/920-task-stack.ax`.
Not yet: the pool starts each task as a process, so `Task` is not
available on Windows, where `parallel` runs on threads. See the
[roadmap](roadmap.md).

Cancellation is checked between every spawn attempt, including while a
wide launch window is filling. An attempt already in progress can race
the token. Once cancellation is observed, the pool starts no more work
and gives running children their grace period before killing and reaping
them. Unstarted slots answer `Err taskCancelledCode` in submit order.
A deadline is per task, measured from its spawn. Tested by
`tests/stdlib/960-task-launch-cancellation.ax`.

`taskMapDecoded` and `taskMapDecodedWith` decode successful
answers into typed values in the parent, in submit order; transport
errors bypass the decoder. The byte limit covers the encoded answer,
so your decoder must bound its own storage. `taskFold` consumes results
with a scalar accumulator instead of retaining a results vector. Each
step's answer and temporary allocations are reclaimed on return.
`scoped(step)` checks that the callback retains neither in captured
state. Pass a lambda directly, a non-nullary function declaration, or a
parameter carrying the same tag. Use `taskMapWith` when answers need to
outlive their delivery. Tested by `tests/stdlib/953-scoped-task-fold.ax`
and `tests/diagnostics/1440-scoped-callback-escape.ax`.

Decoder errors stay in their result slots; `failFast` applies to worker
failures. A slow decoder can delay submission and deadline handling.
Tested by `tests/stdlib/704-task-decoded.ax`.

`taskMapCompute worker count opts` runs checked `(-> Int Int)` workers
and returns `(Vec (Result Int Error))` in submit order. The
`compute(worker)` contract permits primitive captures, numeric helper
calls, explicit conversions and local scalar accumulators. It refuses
references, allocation, captured or heap stores, raw/runtime observers,
foreign calls, assembly and opaque calls, transitively. Local mutation
retains its `Mut` effect; normal type and effect checks still apply.

Each invocation runs in a fresh child. Successful `Int` answers cross as
exactly eight bytes; both `limit` and `keep` count those bytes. Existing
`TaskOpts` cancellation, deadline, fail-fast, memory and stack limits
apply. Convert other numeric results to `Int` explicitly. Tested by
`tests/stdlib/961-task-compute-contract.ax` and
`tests/diagnostics/1445-compute-callback.ax`.

Group small jobs into explicit ranges to reduce process starts:

```scheme
(import IO)
(import Fmt)
(import Vec)
(import Task)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  {
    (let rs (taskMapRanges (lambda (start end) (fmtInt (- end start))) 10 4 (taskOpts 2 8)))
    {
      (for i in 0..(vecLen rs)
        (match (vecGet rs i)
          ((Ok answer) (println answer))
          ((Err error) (println error.code))))
      0
    }
  })
```

```text
4
4
2
```

`taskMapRanges worker count grain opts` covers `0 .. count` once, in
contiguous half-open ranges of at most `grain` items. A non-positive
count starts nothing; a grain below one becomes one. Width bounds
concurrent ranges. Every range runs in a fresh process; work inside
that range shares its child's state. Results stay in range order.

The callback answers one `String` per range. Deadlines, stack and memory
budgets apply to a whole range, and `limit` bounds its answer bytes.
A trapped range answers one `Err`. Choose grain with those costs and
failure boundaries in mind. The range arithmetic accepts the largest
positive `Int` without wrapping. Tested by `tests/stdlib/951-task-ranges.ax`
and `tests/stdlib/952-task-ranges-lifecycle.ax`.

For Float reductions, keep the arithmetic grouping fixed: changing grain
can change rounding.

`taskMapWords` runs word workers and raises the lowest failing index's
status. `taskMapWordsChecked` returns every failure in its own `Result`
slot. Both accept a count and a width, and fork each invocation with its
own copy of captured state. `taskRunCommand` returns one command's
`Result`; `taskRunCommands` runs argument vectors at a bounded width.
Its slots contain exit codes, 128 plus a terminating signal, or a
negative errno when the program could not start.

On Windows 10 and later, command pools use native processes in a private
cleanup job. Results keep submit order, and at most `width` commands are
outstanding. A launch failure occupies its slot; a wait failure ends the
pool and gives its negative errno to the remaining commands. Closing the
pool also terminates descendants still in its job. A host job policy
that refuses containment returns a launch error. Argument quoting and
PATH lookup follow `Sys`; `.bat` and `.cmd` files need an explicit
`cmd.exe` invocation. Only valid standard-stream handles are inherited;
unrelated inheritable handles stay in the parent. Launch buffers are
reused between commands. Tested by `tests/stdlib/987-command-pools.ax`
and the host WinAPI mocks in `tests/platform/windows-command-pools.py`.

### Executable workers

Use `Task.Worker` when a worker can receive and return encoded bytes.
Build a separate executable with an entry point like this:

```scheme
(import Task.Worker)
(import Str)

(:: answer (-> WorkerContext String String))
(fn (answer context input) (concat input "!"))

(:: main Int)
;@axiom:effect(io)
(fn (main) (workerServe (lambda (context input) (answer context input))))
```

The caller supplies its argument vector and input strings:

```scheme
(import Task.Worker)
(import Vec)
(import IO)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  {
    (let argv vecNew)
    (vecPush argv "./worker-endpoint")
    (let inputs vecNew)
    (vecPush inputs "hello")
    (let results (workerMap argv inputs (workerOpts 2 1024 1024)))
    (match (vecGet results 0)
      ((Ok text) (println text))
      ((Err error) (println error.code)))
    0
  })
```

Each input starts a fresh executable. The caller's heap and closures
are never copied into it. Results keep input order; stdout and stderr
remain ordinary side effects. Run the endpoint through `workerMap`:
`workerServe` expects the launcher's transport arguments.

`workerOpts width inputLimit resultLimit` bounds concurrent children
and each message's byte length. Input or result overflow answers error
1003. `workerWithKeep` bounds successful result bytes retained by one
call; exceeding it answers 1012 and cancels remaining work.
`workerWithMemory` bounds additional child arena mappings after its
input is installed. It does not bound the parent's total memory.

Deadlines, cancellation tokens, grace and fail-fast have separate
`workerWith*` setters. A handler polls `workerCancelled context` to
cooperate. Children are joined before the call returns, including after
forced termination. POSIX raw kernel exit or SIGKILL can bypass parent
cleanup; Windows job ownership also handles parent process exit.

The default `NativeStack` uses the executable's ordinary stack.
`StackBytes` requests a guarded usable-byte budget where supported;
Windows refuses it with error 78 before launching a child. A working
monotonic clock is also required. Parent allocator bookkeeping can
remain retained across repeated calls; these options do not establish
flat total parent memory. Tested by `tests/platform/worker-pool.py`
and `tests/platform/worker-lifecycle.py`.

`Chan` passes words
through a bounded channel; `Sync` provides mutexes with timeout and
owner-death reporting. A lock call answers a guard, and the lock is
released when the guard's scope ends. A channel, mutex or token is
freed when its last owner lets go, so there is no free to call. Use
shared handles through their module's public operations. These APIs do not transfer arbitrary heap graphs between
processes or make unsynchronised payload mutation safe.

Read [concurrency](reference.md#concurrency) for capture and result rules.
API: [Task](stdlib-api.md#task), [Task.Worker](stdlib-api.md#taskworker),
[Chan](stdlib-api.md#chan), [Sync](stdlib-api.md#sync).

## Terminals, tests and tools

`Tui.Keys`, `Tui.Edit` and `Tui.Term` decode keys, maintain editing state
and connect it to terminal I/O. `Test` provides labelled assertions for
`axiom test`. `Agent.Tags` reads AXSYM declarations, effects and tags.

See [testing](reference.md#testing), [editor setup](lsp.md) and
[symbol metadata](diagnostics.md#read-symbol-tags). Their signatures are in the
[generated API](stdlib-api.md).

<a id="mem-and-ffi"></a>
## Mem

`Mem` exposes raw allocation and byte/word access. Callers must establish
validity, bounds, alignment and lifetime behind an Unsafe boundary.
Prefer typed owners and containers for application code.

`memStats` safely returns a `MemoryStats` snapshot with `heldBytes`,
`filedBytes`, `mappedBytes` and `backlogBytes`. Counts describe the
calling binding's arena and exclude the snapshot record itself.
Backlog is held less reusable storage; it includes live values and
allocator overhead. It does not count leaks or measure process RSS.
Tested by `tests/stdlib/703-memory-stats.ax`.

`addrOf` answers where a value lives as a sealed `Addr`, which
`addrEq` compares and `addrHash` hashes. It is the way to ask whether
two values are one, or to key a table by identity, without erasing a
value into an `Int`. An `Addr` takes no share, so compare two only
while both values are live. Tested by `tests/stdlib/810-addr-identity.ax`.

Foreign-function helpers live in the axiom-oxide package, not the
standard library: `pkg/axiom-oxide/axiom/Ffi.ax` supports generated
Rust wrappers with handles, result out-cells and byte/vector
conversion. Start at the [Rust FFI guide](ffi.md), then use the
generated operations for each sealed owner.

API: [Mem](stdlib-api.md#mem).
