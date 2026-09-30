# Axiom standard library

Every public function, type and macro in Axiom's standard library, one
section per module. To find out what each module is for, start with
[Modules at a glance](reference.md#modules-at-a-glance) in the language
reference.

Every name listed is `pub` in the source. The columns are:

- **Kind**: `value` for a function or constant, `struct`, `data`,
  `effect` or `macro`.
- **Type**: the signature as you write it in source, such as
  `(-> Int Int)`.
- **Effects**: what the compiler infers the definition does. `Alloc`
  allocates, uses the arena or installs a handler. `IO` reaches the
  outside world through a syscall, an `extern` call or the command
  line. `Mut` changes heap state that something else can see. `Unsafe`
  uses a raw-memory primitive. A blank cell means the compiler inferred
  no effect, and a macro's cell is always blank. Treat the column as a
  lower bound: inference doesn't count the allocation a constructor
  makes (`docs/memory-model.md` MM-EXEC-9a).
- **Summary**: the first paragraph of the comment above the definition.

This page is generated from the standard library by
`examples/axdoc/axdoc.ax`, so please don't edit it by hand.
`scripts/check-stdlib-api.sh` regenerates it in CI and fails if the
two differ.

## `Agent.Tags`

`stdlib/Agent/Tags.ax` — 32 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Meta` | struct |  |  | One `#key` or `#key=value`. A bare flag - `#no_refactor` - has `val` empty, which `symHasTag` distinguishes from an absent key. |
| `Sym` | struct |  |  | One AXSYM line, parsed. |
| `axsymSpace` | value | `Int` |  |  |
| `axsymQuote` | value | `Int` |  |  |
| `axsymHash` | value | `Int` |  |  |
| `axsymAt` | value | `Int` |  |  |
| `axsymEquals` | value | `Int` |  |  |
| `axsymNewline` | value | `Int` |  |  |
| `axsymPercent` | value | `Int` |  |  |
| `axsymIsKind` | value | `(-> Int Bool)` |  | The six KIND letters, and deliberately only those: they are disjoint from AXDL's `E`/`W`/`N`/`H` severity sigils, so a line's first byte says which notation produced it even in a concatenated stream. A seventh kind added to the compiler must be added here, and a line whose first byte is unknown is answered `None` rather than guessed at - a reader that guesses turns a compiler change into silently wrong data. |
| `axsymTrimEnd` | value | `(-> String String)` | `Alloc,Mut` | Trailing spaces off the end of a slice. The head field is taken as the bytes before the opening quote, which includes the space that separated the location from it. |
| `axsymEscapable` | value | `(-> Int Bool)` |  | The bytes `saAxMeta` escapes on the way out, restated here because this is the other end of the same wire: space and every control byte (`< 33`), `"`, `#`, `%` and DEL. Anything else is left alone, so a UTF-8 tag value survives. |
| `axsymHexVal` | value | `(-> Int (Option Int))` |  | One hex digit's value, or `None`. Both cases are accepted: the emitter writes upper, and a reader that took only what one emitter happens to write is pinned to that emitter rather than to the notation. Absence, not failure - `docs/error-model.md` ERR-REC-3 - and `Option` is built in, so this costs the module no import. |
| `axsymPctAt` | value | `(-> String Int (Option Int))` | `Alloc` | The byte a `%XX` at `i` stands for, or `None` where there is no complete escape. STRICT, and that is the point: only the bytes `saAxSafe` escapes decode, so a literal `%` standing in a value the COMPILER built - a rendered type, a generated `Trait#Type#method` name - is never mistaken for an escape. `%41` stays `%41`. |
| `axsymUnpct` | value | `(-> String String)` | `Alloc,Mut` | A meta key or value with its escapes undone. The `strFindByte` guard is not an optimisation for its own sake: no AXTAG in this repository contains a byte that is escaped, so every token on every line in the corpus takes the first arm and is returned as it arrived, allocating nothing and copying nothing. |
| `axsymUnpctFrom` | value | `(-> String Int String String)` | `Alloc,Mut` |  |
| `axsymMeta` | value | `(-> String Meta)` | `Alloc,Mut` | `#key=value` or a bare `#key`, with the leading `#` already dropped. Both halves are unescaped, because `saAxMeta` escapes both: an AXTAG key is everything from `;@axiom:` to the newline, so a key can carry a space or a `#` just as a value can. |
| `axsymMetaScan` | value | `(-> String Int Int (Vec Meta) (Vec Meta))` | `Alloc,Mut` | The metadata section, from `at` to the end of the line. A token opens at a `#` whose previous byte is a space, and runs to the byte before the next such `#`. `i` walks; `start` is the open token's first byte, or -1 before the first `#` is seen. |
| `axsymLine` | value | `(-> String (Option Sym))` | `Alloc,Mut` | One line. `None` for a blank line, for a line whose first byte is not a KIND letter, and for a line with no quoted type - which together are every non-AXSYM line a caller might feed in, including the `compilation failed` trailer and AXDL diagnostics on the same stream. |
| `axsymBuild` | value | `(-> String Int Int (Option Sym))` | `Alloc,Mut` | The three fields either side of the quoted type, once its bounds are known. Split out because the arms above are a refusal ladder and this is the one path that answers a symbol. |
| `axsymNid` | value | `(-> String String)` | `Alloc,Mut` | The `@<nid>` between the type and the metadata, empty when absent. It is bounded by the next space rather than by the end, because the metadata follows it on the same line. |
| `axsymParse` | value | `(-> String (Vec Sym))` | `Alloc,Mut` | A whole AXSYM stream. Lines that are not AXSYM are skipped, so the caller may pass the compiler's output unfiltered. |
| `axsymParseFrom` | value | `(-> (Vec String) Int (Vec Sym) (Vec Sym))` | `Alloc,Mut` |  |
| `symTag` | value | `(-> Sym String String)` |  | The value of the LAST `#key` on the line, or empty. Empty is also what a bare flag answers, so a caller distinguishing "absent" from "present with no value" wants `symHasTag`. |
| `symTagFrom` | value | `(-> (Vec Meta) String Int String)` |  |  |
| `symTagLastIdx` | value | `(-> (Vec Meta) String Int Int Int)` |  | The index of the last `#key` at or after `i`, or -1. Carried in an accumulator rather than compared on the way out of the recursion, because a bare flag's value is empty and "" cannot tell a later match from no match at all. |
| `symHasTag` | value | `(-> Sym String Bool)` |  |  |
| `symHasTagFrom` | value | `(-> (Vec Meta) String Int Bool)` |  |  |
| `symEffects` | value | `(-> Sym String)` |  | The effect row the CHECKER derived - not what the author claimed. Empty when the declaration performs none. |
| `symDerivedPure` | value | `(-> Sym Bool)` |  | True when the checker derived no effects at all. This is a statement about the ANALYSIS, not a guarantee about the program: an effect reached through a function value in memory is not in the row, and a built-in effect named by an enclosing `handle` is subtracted from it. A policy that treats this as proof of purity is reading a lower bound as an upper one. |
| `symAgentTag` | value | `(-> Sym String String)` | `Alloc,Mut` | The `agent:*` namespace, which the compiler records and does not check. `(symAgentTag s "rewrite")` reads `#agent:rewrite`. |
| `symHasAgentTag` | value | `(-> Sym String Bool)` | `Alloc,Mut` |  |

## `Chan`

`stdlib/Chan.ax` — 15 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Chan` | struct |  |  | A channel: one word, a slot in the runtime's handle table (MM-PAR-8) naming the ring's mapping. |
| `chanOwnerDead` | value | `Int` |  | What a timed call answers on a channel whose lock holder died: the mutex's `syncOwnerDead`, the same code for the same event. Above 255, like `sysTimedOut`, so it cannot be mistaken for a wait status. |
| `chanNew` | value | `(-> Int (Result Chan Error))` | `Alloc,IO,Mut` | A channel of `cap` words, 1 <= cap <= 1,048,576. Answers the handle, or the mapping's error; a capacity out of range is EINVAL (22 on every target with a syscall ABI), and a handle table with no slot left is EMFILE (24). |
| `chanSend` | value | `(-> Chan Int Bool)` | `Alloc,IO,Mut` | Send `v`, waiting while the ring is full. `True` once it is in the ring; `False` if the channel is closed - before the call or while it waited - or poisoned (`chanPoisoned`), and then `v` was not sent. |
| `chanRecv` | value | `(-> Chan (Option Int))` | `Alloc,IO,Mut` | Receive the oldest word, waiting while the ring is empty and open. `None` once the channel is closed AND drained - the end of the stream - or poisoned (`chanPoisoned`). |
| `chanSendTimeout` | value | `(-> Chan Int Int (Result Bool Error))` | `Alloc,IO,Mut,Unsafe` | `chanSend`, waiting at most `nanos` nanoseconds - for the lock and for room. `Ok True` once `v` is in the ring; `Ok False` if the channel is closed; `Err` with code `sysTimedOut` when the time ran out first, and `Err` with code `chanOwnerDead` when the channel is poisoned - and in each of those `v` was not sent. The ring is looked at once more after the last wait, so a slot that opened as the time ran out is taken rather than refused. A non-positive `nanos` is one look, like `chanTrySend`, that says which it was. |
| `chanRecvTimeout` | value | `(-> Chan Int (Result (Option Int) Error))` | `Alloc,IO,Mut,Unsafe` | `chanRecv`, waiting at most `nanos` nanoseconds - for the lock and for a word. `Ok (Some w)` the oldest word; `Ok None` the end of the stream (closed and drained); `Err` with code `sysTimedOut` when the time ran out first - the defined answer on timeout, which takes nothing out of the ring - and `Err` with code `chanOwnerDead` when the channel is poisoned. A non-positive `nanos` is one look. |
| `chanTrySend` | value | `(-> Chan Int Bool)` | `Alloc,IO,Mut` | Send without waiting for room: `True` if `v` went into the ring, `False` if it did not - full, closed or poisoned, which `chanClosed` and `chanPoisoned` tell apart, as they do for `chanTryRecv`. A `Bool` rather than a three-way `Int`: a -1 for "closed" is the sentinel convention the error model is migrating away from (`tests/compat/verify-compat.py`). |
| `chanTryRecv` | value | `(-> Chan (Option Int))` | `Alloc,IO,Mut` | Receive without waiting for a word: the oldest word, or `None` when there is none right now - empty, whether or not it is closed, or poisoned; `chanClosed` and `chanPoisoned` tell them apart. |
| `chanClose` | value | `(-> Chan Int)` | `Alloc,IO,Mut` | End the stream. Idempotent. Every waiter wakes: a sender to be refused, a receiver to drain and then see `None`. A poisoned channel has ended already, and this changes nothing. |
| `chanClosed` | value | `(-> Chan Bool)` | `Alloc,IO,Mut` | Whether the stream has ended: closed, or poisoned. |
| `chanPoisoned` | value | `(-> Chan Bool)` |  | Whether a binding died holding this channel's lock, which poisoned it (the module header's "a holder that dies"). Takes no lock. |
| `chanLen` | value | `(-> Chan Int)` | `Alloc,IO,Mut` | Words in the ring now; 0 on a poisoned channel, which yields none. |
| `chanCap` | value | `(-> Chan Int)` |  |  |
| `chanFree` | value | `(-> Chan (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Unmap the channel. Only once no binding can still reach it - after the `parallel` form that used it (the module header's obligation). The handle is retired before the ring is unmapped, so every call made after this one - a second `chanFree` included - traps with status 85. It takes no lock, so a poisoned channel is freed like any other. |

## `Crypto.Aead`

`stdlib/Crypto/Aead.ax` — 11 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `AeadNonce` | struct |  |  | A 12-byte nonce for one AEAD message. Build it with `aeadNonceFromBytes`, `aeadNonceRandom` or `nonceSequenceNext`; the AEADs refuse one of any other length. |
| `aeadNonceLen` | value | `Int` |  | The nonce length the AEADs take: 12 bytes. |
| `aeadTagLen` | value | `Int` |  | The tag every seal appends and every open checks: 16 bytes. Shorter tags are not offered. |
| `aeadNonceFromBytes` | value | `(-> String (Result AeadNonce Error))` | `Alloc,Mut,Unsafe` | A nonce holding a copy of `b`, which must be exactly 12 bytes. Anything else answers `cryptoInvalidLength`: other nonce lengths exist in GCM, and this suite does not take them. |
| `aeadNonceBytes` | value | `(-> AeadNonce String)` |  | The nonce's 12 bytes, to send beside the ciphertext. |
| `aeadNonceRandom` | value | `(Result AeadNonce Error)` | `Alloc,IO,Mut` | A nonce of 12 bytes from the kernel's entropy source. Use at most 2^32 random nonces under one key (SP 800-38D 8.3); the module header says why. |
| `NonceSequence` | struct |  |  | A source of nonces that never repeats: a fixed 4-byte prefix and a 64-bit big-endian counter, the prefix and invocation fields of SP 800-38D 8.2.1. The state is the next nonce itself, 12 bytes. The counter runs from 0 to 2^63 - 2, and one sequence is not safe to use from two threads at once. |
| `nonceSequenceNew` | value | `(-> String (Result NonceSequence Error))` | `Alloc,Mut` | A sequence whose first nonce is `prefix` followed by a zero counter. `prefix` must be 4 bytes, and distinct for every sender that shares the key. |
| `nonceSequenceResume` | value | `(-> String Int (Result NonceSequence Error))` | `Alloc,Mut` | A sequence that carries on from `position`, a value read back from `nonceSequencePosition` and persisted before the nonce it followed was used. `position` is 0 to 2^63 - 1; at 2^63 - 1 the sequence is already used up. |
| `nonceSequenceNext` | value | `(-> NonceSequence (Result AeadNonce Error))` | `Alloc,Mut,Unsafe` | The next nonce, and the counter moved on past it. Once the counter reaches 2^63 - 1 every call answers `cryptoLimitExceeded`: the sequence never wraps round to a nonce it has given out. A state that is not 12 bytes answers `cryptoInvalidLength`. |
| `nonceSequencePosition` | value | `(-> NonceSequence Int)` | `Unsafe` | The counter the next nonce will carry: the value to persist, before sealing, so a restart can resume after every nonce already given out. -1 for a state that is not 12 bytes. |

## `Crypto.Aes`

`stdlib/Crypto/Aes.ax` — 9 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `aesRounds` | value | `(-> Int Int)` |  | The number of rounds for a key of `keyLen` bytes: 10, 12 or 14 for 16, 24 or 32, and 0 for any other length. |
| `aesScheduleBytes` | value | `(-> Int Int)` |  | The bytes an expanded schedule for a key of `keyLen` bytes occupies: eight words per round key, 704, 832 or 960. 0 for a bad length. |
| `aesKeyWorkBytes` | value | `Int` |  | The scratch `aesKeyExpand` needs: the 60-word FIPS 197 schedule and an 8-word state. |
| `aesStateBytes` | value | `Int` |  | The bitsliced state: eight words, four blocks. |
| `aesCtrWorkBytes` | value | `Int` |  | The scratch `aesCtr32Xor` needs: the state and one 64-byte run of keystream. |
| `aesKeyExpand` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` | Expand the `keyLen`-byte key at `key` into the bitsliced schedule at `out`, `aesScheduleBytes keyLen` bytes. Answers the number of rounds, or 0, writing nothing, when `keyLen` is not 16, 24 or 32. The scratch at `work` is wiped before this returns. |
| `aesEncryptBlocks` | value | `(-> Int Int Int Int Int Int Int)` | `Mut,Unsafe` | Encrypt `n` 16-byte blocks from `src` to `dst`, each on its own (the raw cipher, FIPS 197 5.1; ECB when read as a mode). `src` and `dst` may be the same address. `q` is scratch the caller wipes. |
| `aesDecryptBlocks` | value | `(-> Int Int Int Int Int Int Int)` | `Mut,Unsafe` | Decrypt `n` 16-byte blocks from `src` to `dst` (FIPS 197 5.3). |
| `aesCtr32Xor` | value | `(-> Int Int Int Int Int Int Int Int Int)` | `Mut,Unsafe` | XOR `len` bytes from `src` with the keystream E(iv \|\| ctr), E(iv \|\| ctr + 1), ... into `dst`, where `iv` is 12 bytes and the counter is the last 4 bytes of each block, big-endian, incremented modulo 2^32. Answers the counter after the last block used. `src` and `dst` may be the same address. `work` holds keystream when this returns; the caller wipes it. |

## `Crypto.AesGcm`

`stdlib/Crypto/AesGcm.ax` — 14 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Aes128GcmKey` | struct |  |  | An AES-128-GCM key: 16 bytes, with its schedule and hash key, in the secret store (kind 19). |
| `Aes256GcmKey` | struct |  |  | An AES-256-GCM key: 32 bytes, with its schedule and hash key, in the secret store (kind 20). |
| `aes128GcmKeyGenerate` | value | `(Result Aes128GcmKey Error)` | `Alloc,IO,Mut,Unsafe` | A fresh random AES-128-GCM key from the kernel's entropy source. |
| `aes256GcmKeyGenerate` | value | `(Result Aes256GcmKey Error)` | `Alloc,IO,Mut,Unsafe` | A fresh random AES-256-GCM key from the kernel's entropy source. |
| `aes128GcmKeyFromSecret` | value | `(-> SecretBytes (Result Aes128GcmKey Error))` | `Alloc,IO,Mut,Unsafe` | An AES-128-GCM key holding a copy of `s`, which must be 16 bytes. This is also the deterministic way to make a key, for known-answer tests and protocols that derive one; `s` is left as it was. |
| `aes256GcmKeyFromSecret` | value | `(-> SecretBytes (Result Aes256GcmKey Error))` | `Alloc,IO,Mut,Unsafe` | An AES-256-GCM key holding a copy of `s`, which must be 32 bytes. |
| `aes128GcmKeyExport` | value | `(-> Aes128GcmKey (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | The key's 16 bytes as a new `SecretBytes`, for storing it somewhere you trust. The key itself stays live. |
| `aes256GcmKeyExport` | value | `(-> Aes256GcmKey (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | The key's 32 bytes as a new `SecretBytes`. |
| `aes128GcmKeyWipe` | value | `(-> Aes128GcmKey Int)` | `Alloc,IO,Mut,Unsafe` | Erase the key, its schedule and its hash key, and free the store. Any later use of `k` stops the program with status 85. Answers 0. |
| `aes256GcmKeyWipe` | value | `(-> Aes256GcmKey Int)` | `Alloc,IO,Mut,Unsafe` | Erase an AES-256-GCM key and free the store. Answers 0. |
| `aes128GcmSeal` | value | `(-> Aes128GcmKey AeadNonce String String (Result String Error))` | `Alloc,Mut,Unsafe` | Encrypt and authenticate `plaintext` with `aad` under `key` and `nonce`: the ciphertext, the same length as the plaintext, followed by the 16-byte tag. The nonce must never have been used with this key before. |
| `aes128GcmOpen` | value | `(-> Aes128GcmKey AeadNonce String String (Result String Error))` | `Alloc,Mut,Unsafe` | Check and decrypt `sealed` (ciphertext \|\| tag) with `aad` under `key` and `nonce`: the plaintext, or `cryptoAuthFailed` for any failure. Nothing is decrypted unless the tag matches. |
| `aes256GcmSeal` | value | `(-> Aes256GcmKey AeadNonce String String (Result String Error))` | `Alloc,Mut,Unsafe` | Encrypt and authenticate with AES-256-GCM: ciphertext \|\| 16-byte tag. |
| `aes256GcmOpen` | value | `(-> Aes256GcmKey AeadNonce String String (Result String Error))` | `Alloc,Mut,Unsafe` | Check and decrypt an AES-256-GCM message: the plaintext, or `cryptoAuthFailed` for any failure. |

## `Crypto.Blake2b`

`stdlib/Crypto/Blake2b.ax` — 14 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `blake2bCompress` | value | `(-> Int Int Int Bool Int)` | `Mut,Unsafe` | Fold one 128-byte block at `p` into the chaining value in words 0-7 at `st`, after advancing the byte counter in words 8 and 9 by `inc`; `last` sets the final-block flag. This is F of RFC 7693 section 3.2 with its counter bookkeeping, for a caller building its own mode over BLAKE2b. Answers 0. |
| `blake2bAddr` | value | `(-> Int Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | The BLAKE2b digest of `n` bytes at `p`, `outLen` bytes long and keyed with the `keyLen` bytes at `key`, written to `out`. The scratch state is erased before it returns. Answers 0. |
| `blake2b` | value | `(-> Int String String (Result String Error))` | `Alloc,Mut,Unsafe` | The `outLen`-byte BLAKE2b digest of `msg` keyed with `key`; an empty key is unkeyed BLAKE2b. A digest length outside 1 to 64 or a key over 64 bytes answers `cryptoInvalidLength`. |
| `blake2b512` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 64-byte unkeyed BLAKE2b digest of `msg` (BLAKE2b-512). |
| `blake2b256` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 32-byte unkeyed BLAKE2b digest of `msg` (BLAKE2b-256). |
| `Blake2b` | struct |  |  | A BLAKE2b hash in progress. Make one with `blake2bNew` or `blake2bNewKeyed`. |
| `blake2bNew` | value | `(-> Int (Result Blake2b Error))` | `Alloc,Mut,Unsafe` | A fresh unkeyed hash with an `outLen`-byte digest, or `cryptoInvalidLength` when `outLen` is outside 1 to 64. |
| `blake2bNewKeyed` | value | `(-> Int String (Result Blake2b Error))` | `Alloc,Mut,Unsafe` | A fresh hash with an `outLen`-byte digest keyed with `key`, or `cryptoInvalidLength` when `outLen` is outside 1 to 64 or `key` is over 64 bytes. The state keeps a copy of the key until it is wiped. |
| `blake2bNewKeyedSecret` | value | `(-> Int SecretBytes (Result Blake2b Error))` | `Alloc,Mut,Unsafe` | `blake2bNewKeyed` with a key held in the secret store. |
| `blake2bUpdateAddr` | value | `(-> Blake2b Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`. Answers 0, or -1 when `h` is not a live BLAKE2b state or `n` is negative, and then absorbs nothing. |
| `blake2bUpdate` | value | `(-> Blake2b String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `h` is not a live BLAKE2b state. |
| `blake2bFinal` | value | `(-> Blake2b String)` | `Alloc,Mut,Unsafe` | The digest of everything absorbed, as long as `h` was made to give. `h` is then reset to a fresh hash with the same digest length and key. A value that is not a live BLAKE2b state answers the empty string. |
| `blake2bCopy` | value | `(-> Blake2b Blake2b)` | `Alloc,Mut,Unsafe` | An independent copy of `h`, which goes on from the same point. It holds its own copy of any key. |
| `blake2bWipe` | value | `(-> Blake2b Int)` | `Mut,Unsafe` | Erase everything `h` holds, the key included. Every later operation on it is refused. Answers 0, or -1 with nothing written when `h` is not a BLAKE2b state. |

## `Crypto.Bytes`

`stdlib/Crypto/Bytes.ax` — 16 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `bytesNew` | value | `(-> Int String)` | `Alloc,Mut` | `n` zero bytes, as a fresh string a caller may write into through `strData` before handing it on. |
| `bytesFromAddr` | value | `(-> Int Int String)` | `Alloc,Mut,Unsafe` | A fresh copy of `n` bytes at `p`. |
| `bytesU32Be` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | The 4 bytes of `v`'s low 32 bits, most significant first. |
| `bytesU32Le` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | The 4 bytes of `v`'s low 32 bits, least significant first. |
| `bytesU64Be` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | The 8 bytes of `v`, most significant first. |
| `bytesU64Le` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | The 8 bytes of `v`, least significant first. |
| `bytesXor` | value | `(-> String String (Result String Error))` | `Alloc,Mut,Unsafe` | The byte-wise XOR of two strings of the same length, or `Err` when the lengths differ. |
| `bytesEqCt` | value | `(-> String String Bool)` | `Mut,Unsafe` | Whether `a` and `b` hold the same bytes, in time that depends only on their lengths. Lengths are public here: two strings of different lengths answer false at once. Use this, never `==` or `strEq`, to compare a tag, a digest of a secret, or anything else an attacker could learn from how long a comparison took. |
| `hexEncode` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | `s`'s bytes as lower-case hex, two digits a byte. |
| `hexDecode` | value | `(-> String (Result String Error))` | `Alloc,Mut,Unsafe` | The bytes a hex string spells, or `Err` when its length is odd or any character is not a hex digit. Upper- and lower-case both decode. |
| `b64Encode` | value | `(-> String String)` | `Alloc,Mut` | Standard base64 with '=' padding, as RFC 4648 section 4 writes it. |
| `b64EncodeNoPad` | value | `(-> String String)` | `Alloc,Mut` | Standard base64 without padding: the spelling of the PHC string format that password records use. |
| `b64UrlEncode` | value | `(-> String String)` | `Alloc,Mut` | URL-safe base64 without padding (RFC 4648 section 5), for tokens that go in a URL or a file name. |
| `b64Decode` | value | `(-> String (Result String Error))` | `Alloc,Mut` | Decode padded standard base64. The length must be a multiple of four and the padding exactly what the length calls for. |
| `b64DecodeNoPad` | value | `(-> String (Result String Error))` | `Alloc,Mut` | Decode standard base64 that carries no padding. An '=' anywhere is refused. |
| `b64UrlDecode` | value | `(-> String (Result String Error))` | `Alloc,Mut` | Decode URL-safe base64 without padding. |

## `Crypto.ChaCha20`

`stdlib/Crypto/ChaCha20.ax` — 3 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `chacha20BlockBytes` | value | `Int` |  | The bytes `chacha20Block` writes through: 64 of keystream, then 64 of scratch it wipes. |
| `chacha20Block` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` | Write keystream block `counter` for the 32-byte key at `key` and the 12-byte nonce at `nonce` to the first 64 bytes at `out` (RFC 8439 2.3): the state after 20 rounds, ten column rounds alternating with ten diagonal rounds, added word by word to the state it started from. `out` also holds the working state, so it names `chacha20BlockBytes`; the second 64 bytes are wiped before this returns. `counter` is taken modulo 2^32. |
| `chacha20Xor` | value | `(-> Int Int Int Int Int Int Int Int)` | `Mut,Unsafe` | XOR `len` bytes from `src` with the keystream starting at block `counter` into `dst` (RFC 8439 2.4). `src` and `dst` may be the same address. `work` is `chacha20BlockBytes` of scratch; its first 64 bytes hold the last keystream block when this returns, and the caller wipes them. Answers the counter after the last block used. The caller keeps `counter` plus the number of blocks within 2^32. |

## `Crypto.ChaCha20Poly1305`

`stdlib/Crypto/ChaCha20Poly1305.ax` — 7 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `ChaCha20Poly1305Key` | struct |  |  | A ChaCha20-Poly1305 key: 32 bytes in the secret store (kind 21). |
| `chacha20Poly1305KeyGenerate` | value | `(Result ChaCha20Poly1305Key Error)` | `Alloc,IO,Mut,Unsafe` | A fresh random ChaCha20-Poly1305 key from the kernel's entropy source, drawn straight into the secret store. |
| `chacha20Poly1305KeyFromSecret` | value | `(-> SecretBytes (Result ChaCha20Poly1305Key Error))` | `Alloc,IO,Mut,Unsafe` | A key holding a copy of `s`, which must be 32 bytes. This is also the deterministic way to make a key, for known-answer tests and protocols that derive one; `s` is left as it was. |
| `chacha20Poly1305KeyExport` | value | `(-> ChaCha20Poly1305Key (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | The key's 32 bytes as a new `SecretBytes`, for storing it somewhere you trust. The key itself stays live. |
| `chacha20Poly1305KeyWipe` | value | `(-> ChaCha20Poly1305Key Int)` | `Alloc,IO,Mut,Unsafe` | Erase the key and free the store. Any later use of `k` stops the program with status 85. Answers 0. |
| `chacha20Poly1305Seal` | value | `(-> ChaCha20Poly1305Key AeadNonce String String (Result String Error))` | `Alloc,Mut,Unsafe` | Encrypt and authenticate `plaintext` with `aad` under `key` and `nonce`: the ciphertext, the same length as the plaintext, followed by the 16-byte tag. The nonce must never have been used with this key before. A nonce that is not 12 bytes answers `cryptoInvalidLength`, and a plaintext over the limit `cryptoLimitExceeded`. |
| `chacha20Poly1305Open` | value | `(-> ChaCha20Poly1305Key AeadNonce String String (Result String Error))` | `Alloc,Mut,Unsafe` | Check and decrypt `sealed` (ciphertext \|\| tag) with `aad` under `key` and `nonce`: the plaintext, or `cryptoAuthFailed` for any failure. Nothing is decrypted unless the tag matches. |

## `Crypto.Ct`

`stdlib/Crypto/Ct.ax` — 27 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `ctBarrier` | value | `(-> Int Int)` | `Mut,Unsafe` | `x`, unchanged, through an empty assembly block: the optimiser has to treat the answer as any word at all. This is what stops a mask from being reasoned back into a branch. |
| `ctMaskNz` | value | `(-> Int Int)` | `Mut` | -1 when `x` is not zero, 0 when it is. For any nonzero `x`, one of `x` and `-x` has the sign bit set (for the most negative word both do), so an arithmetic shift of their `\|` spreads it. |
| `ctMaskZero` | value | `(-> Int Int)` | `Mut` | -1 when `x` is zero, 0 when it is not. |
| `ctMaskEq` | value | `(-> Int Int Int)` | `Mut` | -1 when `a` equals `b`, 0 otherwise. |
| `ctMaskLtU` | value | `(-> Int Int Int)` | `Mut` | -1 when `a` is below `b` as UNSIGNED 64-bit words, 0 otherwise. This is the borrow out of `a - b`, computed from the operands' top bits (Hacker's Delight 2-13), so it is right across the whole range where the signed `(- a b)` would overflow. |
| `ctMaskNeg` | value | `(-> Int Int)` | `Mut` | -1 when `x` is negative, 0 otherwise. |
| `ctSelect` | value | `(-> Int Int Int Int)` |  | `a` where `m` is -1, `b` where `m` is 0. `m` must be a mask. |
| `ctMaskFromBit` | value | `(-> Int Int)` | `Mut` | A mask from a 0/1 bit: 1 becomes -1 and 0 stays 0. |
| `shrU` | value | `(-> Int Int Int)` |  | `x` shifted right by `n` bits with zeros in, for 1 <= n <= 63. |
| `rotl64` | value | `(-> Int Int Int)` |  | A 64-bit rotation left by `n`, for 1 <= n <= 63. |
| `rotr64` | value | `(-> Int Int Int)` |  | A 64-bit rotation right by `n`, for 1 <= n <= 63. |
| `mask32` | value | `Int` |  | The 32-bit words a SHA-256 or ChaCha20 state holds live in the low half of an Int with the high half zero, so `>>` on one is already logical. Every operation that can carry into the high half masks back to 32 bits. |
| `rotl32` | value | `(-> Int Int Int)` |  | A 32-bit rotation left by `n`, for 1 <= n <= 31, of a word in 0..2^32-1. The answer is in the same range. |
| `rotr32` | value | `(-> Int Int Int)` |  | A 32-bit rotation right by `n`, for 1 <= n <= 31. |
| `add32` | value | `(-> Int Int Int)` |  | `a + b` modulo 2^32, for words in 0..2^32-1. |
| `ld32le` | value | `(-> Int Int Int)` | `Unsafe` |  |
| `ld32be` | value | `(-> Int Int Int)` | `Unsafe` |  |
| `ld64le` | value | `(-> Int Int Int)` | `Unsafe` |  |
| `ld64be` | value | `(-> Int Int Int)` | `Unsafe` |  |
| `st32le` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  |
| `st32be` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  |
| `st64le` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  |
| `st64be` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  |
| `ctEqAddr` | value | `(-> Int Int Int Bool)` | `Mut,Unsafe` | Whether `n` bytes at `a` and at `b` are equal, taking the same time whichever bytes differ. `n` is public; the contents are not. The running difference passes through the barrier once per byte, so the loop cannot be rewritten to stop at the first difference. |
| `ctWipe` | value | `(-> Int Int Int)` | `Mut,Unsafe` | Overwrite `n` bytes at `p` with zeros, in a way the optimiser may not delete. Answers 0. |
| `ctCopy` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | Copy `n` bytes from `src` to `dst`, which must not overlap. The same loop as `memCopy`; here so a Crypto module needs one import for its memory work. |
| `ctSwapWords` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` | Conditionally swap `n` words at `a` and `b`: swapped where `m` is -1, left alone where `m` is 0. The Montgomery ladder's step, and any other choice between two buffers a secret makes. |

## `Crypto.Curve25519`

`stdlib/Crypto/Curve25519.ax` — 23 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `ge25519P2Bytes` | value | `Int` |  | Bytes in a P2 point (X:Y:Z). |
| `ge25519P3Bytes` | value | `Int` |  | Bytes in a P3 point (X:Y:Z:T). |
| `ge25519P1P1Bytes` | value | `Int` |  | Bytes in a P1P1 point, the output of an addition or doubling. |
| `ge25519PrecompBytes` | value | `Int` |  | Bytes in a Precomp point (y+x, y-x, 2dxy). |
| `ge25519CachedBytes` | value | `Int` |  | Bytes in a Cached point (Y+X, Y-X, Z, 2dT). |
| `ge25519D` | value | `(-> Int Int)` | `Mut,Unsafe` | The curve constant d = -121665/121666 (ref10's d.h). |
| `ge25519D2` | value | `(-> Int Int)` | `Mut,Unsafe` | 2d (ref10's d2.h). |
| `ge25519Base` | value | `(-> Int Int)` | `Mut,Unsafe` | The base point B = (x, 4/5) with x even (RFC 8032, section 5.1), as a P3 at `h`. |
| `ge25519P3Zero` | value | `(-> Int Int)` | `Mut,Unsafe` | The neutral element (0, 1) as a P3. |
| `ge25519P2Zero` | value | `(-> Int Int)` | `Mut,Unsafe` | The neutral element as a P2. |
| `ge25519P1P1ToP2` | value | `(-> Int Int Int)` | `Mut,Unsafe` | r = p as a P2 (ge_p1p1_to_p2). |
| `ge25519P1P1ToP3` | value | `(-> Int Int Int)` | `Mut,Unsafe` | r = p as a P3 (ge_p1p1_to_p3). |
| `ge25519P3ToCached` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | r = p as a Cached point (ge_p3_to_cached). `t` is one field element of scratch. |
| `ge25519P2Dbl` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | r = 2p, for a P2 (or a P3's first three coordinates) at `p` (ge_p2_dbl.h). `t` is one field element of scratch. |
| `ge25519Add` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` | r = p + q, for a P3 `p` and a Cached `q` (ge_add.h). `t` is one field element of scratch. |
| `ge25519Sub` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` | r = p - q, for a P3 `p` and a Cached `q` (ge_sub.h). |
| `ge25519Madd` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` | r = p + q, for a P3 `p` and a Precomp `q` (ge_madd.h). |
| `ge25519ToBytes` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` | Write the 32-byte encoding of the P2 (or P3) at `h` at `s`: y, with the low bit of x in bit 255 (ge_tobytes.c). |
| `ge25519FromBytesVartime` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` | Decode the 32 bytes at `s` into the P3 at `h`, strictly (RFC 8032, section 5.1.3): answers 0, or -1 when y is not below p, when no x satisfies the curve equation, or when x is 0 and the sign bit is set, and `h` is then unspecified. Variable time: for public keys and signatures only. Points of small order decode; nothing here asks what order a point has. |
| `ge25519P3Neg` | value | `(-> Int Int)` | `Mut,Unsafe` | h = -h, for a P3. |
| `ge25519CombTable` | value | `(-> Int Int)` | `Mut,Unsafe` | The two combs as sixteen Precomp points at `t`: entry j of the low comb (0 <= j < 8) is 2^96 B + sum over k < 3 of (+/-) 2^(32k) B, the sign of 2^(32k) B being bit k of j; the high comb, entries 8 to 15, is 2^128 times the low. These are Monocypher's b_comb_low and b_comb_high; tests/crypto/302-curve25519-group.ax recomputes them. |
| `ge25519ScalarMultBase` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` | h = [a]B for the 32-byte scalar at `a`, any value below 2^256, in time that does not depend on `a`. |
| `ge25519DoubleScalarMultVartime` | value | `(-> Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | r = [a]A + [b]B, as a P2, for 32-byte scalars `a` and `b` below 2^253 and the P3 `A`. Variable time: for verification only. |

## `Crypto.Curve25519Scalar`

`stdlib/Crypto/Curve25519Scalar.ax` — 3 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `sc25519Reduce` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` | Write the 64 little-endian bytes at `in` reduced modulo L as 32 bytes at `out`. |
| `sc25519MulAdd` | value | `(-> Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | Write (a b + c) mod L as 32 bytes at `out`, for 32-byte scalars `a`, `b` and `c` of any value below 2^256. |
| `sc25519IsCanonical` | value | `(-> Int Int)` | `Alloc,Mut,Unsafe` | 1 when the 32-byte scalar at `s` is below L - the canonical range RFC 8032, section 5.1.7, requires of a signature's S - and 0 otherwise. |

## `Crypto.Ed25519`

`stdlib/Crypto/Ed25519.ax` — 14 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Ed25519SecretKey` | struct |  |  | An Ed25519 private key: a handle to the seed and what it expands to, in the secret store. Prints as `<Ed25519SecretKey>`. |
| `Ed25519PublicKey` | struct |  |  | An Ed25519 public key: a point's 32-byte encoding. Build one with `ed25519PublicKeyFromBytes`, which checks it. |
| `Ed25519Signature` | struct |  |  | An Ed25519 signature: R (32 bytes) then S (32 bytes). Build one from bytes with `ed25519SignatureFromBytes`, which checks it. |
| `ed25519KeyGenerate` | value | `(Result Ed25519SecretKey Error)` | `Alloc,IO,Mut,Unsafe` | A fresh key from a random 32-byte seed. |
| `ed25519KeyFromSecret` | value | `(-> SecretBytes (Result Ed25519SecretKey Error))` | `Alloc,IO,Mut,Unsafe` | The key whose 32-byte seed is `s` (RFC 8032's private key). `s` is copied, not consumed. This is the deterministic route: for known-answer tests, for restoring a key saved with `ed25519KeyExport`, and for protocols that derive the seed themselves. |
| `ed25519KeyWipe` | value | `(-> Ed25519SecretKey Int)` | `Alloc,IO,Mut,Unsafe` | Erase `k` and free its storage. Any later use of `k` stops the program with status 85. Answers 0. |
| `ed25519KeyExport` | value | `(-> Ed25519SecretKey (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | The 32-byte seed of `k`, as a new `SecretBytes`: RFC 8032's private key, the standard serialisation. `ed25519KeyFromSecret` reads it back. |
| `ed25519PublicKey` | value | `(-> Ed25519SecretKey Ed25519PublicKey)` | `Alloc,Mut,Unsafe` | The public key of `k`. |
| `ed25519PublicKeyFromBytes` | value | `(-> String (Result Ed25519PublicKey Error))` | `Alloc,Mut,Unsafe` | A public key from its 32 bytes. `cryptoInvalidLength` for any other length, and `cryptoInvalidEncoding` unless the bytes are the strict encoding of a point: y below p, x recoverable, and no sign bit on x = 0. |
| `ed25519PublicKeyBytes` | value | `(-> Ed25519PublicKey String)` |  | The 32 bytes of a public key. |
| `ed25519SignatureFromBytes` | value | `(-> String (Result Ed25519Signature Error))` | `Alloc,Mut,Unsafe` | A signature from its 64 bytes. `cryptoInvalidLength` for any other length, and `cryptoInvalidEncoding` when R is not the strict encoding of a point or S is not below L. |
| `ed25519SignatureBytes` | value | `(-> Ed25519Signature String)` |  | The 64 bytes of a signature. |
| `ed25519Sign` | value | `(-> Ed25519SecretKey String Ed25519Signature)` | `Alloc,Mut,Unsafe` | The signature of `msg` under `k` (section 5.1.6): r = SHA-512(prefix \|\| msg) mod L, R = [r]B, k = SHA-512(R \|\| A \|\| msg) mod L, S = (r + k a) mod L. |
| `ed25519Verify` | value | `(-> Ed25519PublicKey String Ed25519Signature Bool)` | `Alloc,Mut,Unsafe` | Whether `sig` is a valid signature of `msg` under `pk` (section 5.1.7): false for a public key or signature of the wrong length, a public key that is not a strict encoding, an S not below L, and whenever [S]B - [k]A does not encode to R. See HOW VERIFICATION DECIDES above. |

## `Crypto.Errors`

`stdlib/Crypto/Errors.ax` — 12 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `cryptoInvalidLength` | value | `Int` |  | A key, nonce, tag, salt, output length or input length that the algorithm does not accept. |
| `cryptoInvalidEncoding` | value | `Int` |  | Bytes that do not decode: bad hex or base64, a public key or signature that is not a canonical encoding, a malformed password record. |
| `cryptoAuthFailed` | value | `Int` |  | Authenticated decryption or tag verification failed. Nothing about the plaintext is released when this is answered. |
| `cryptoEntropyUnavailable` | value | `Int` |  | This target has no secure entropy source Axiom can reach. There is no fallback: the suite never substitutes a clock, a process id or a counter. |
| `cryptoEntropyFailed` | value | `Int` |  | The kernel's entropy call failed. The context carries its errno. |
| `cryptoLimitExceeded` | value | `Int` |  | A usage limit was reached: a message longer than the algorithm may process, or a nonce sequence that has run out. |
| `cryptoUnsupported` | value | `Int` |  | Parameters this implementation does not support. |
| `cryptoNoSecretStore` | value | `Int` |  | The secret store could not make room: the kernel refused a mapping, or the runtime's handle table is full. |
| `cryptoInvalidKey` | value | `Int` |  | A key that decodes but must not be used, such as an X25519 peer key that gives the all-zero shared secret. |
| `cryptoErr` | value | `(-> Int String String (Result a Error))` | `Alloc` | An `Err` carrying one of the codes above, with a message and the name of the function that raised it as context. |
| `cryptoAuthErr` | value | `(-> String (Result a Error))` | `Alloc` | The one authentication failure every open and verify answers. |
| `cryptoLengthErr` | value | `(-> String String (Result a Error))` | `Alloc,Mut` | A length refusal naming what was wrong. |

## `Crypto.Field25519`

`stdlib/Crypto/Field25519.ax` — 21 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `fe25519Bytes` | value | `Int` |  | The size of one field element in bytes: ten 64-bit limbs. |
| `fe25519Set` | value | `(-> Int Int Int Int Int Int Int Int Int Int Int Int)` | `Mut,Unsafe` | Store the ten limbs of a constant at `out`. Answers 0. |
| `fe25519Zero` | value | `(-> Int Int)` | `Mut,Unsafe` | out = 0. |
| `fe25519One` | value | `(-> Int Int)` | `Mut,Unsafe` | out = 1. |
| `fe25519Copy` | value | `(-> Int Int Int)` | `Mut,Unsafe` | out = a. |
| `fe25519SqrtM1` | value | `(-> Int Int)` | `Mut,Unsafe` | A square root of -1 modulo p (ref10's sqrtm1.h). |
| `fe25519Add` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | out = a + b. |
| `fe25519Sub` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | out = a - b. |
| `fe25519Neg` | value | `(-> Int Int Int)` | `Mut,Unsafe` | out = -a. |
| `fe25519Mul` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | out = a * b, reduced. |
| `fe25519Sq` | value | `(-> Int Int Int)` | `Mut,Unsafe` | out = a^2, reduced. |
| `fe25519Sq2` | value | `(-> Int Int Int)` | `Mut,Unsafe` | out = 2 a^2, reduced: the square with every product doubled before the carry, as ref10's fe_sq2 does for point doubling. |
| `fe25519Mul121666` | value | `(-> Int Int Int)` | `Mut,Unsafe` | out = 121666 a, reduced: the constant (A + 2) / 4 of RFC 7748's ladder, where A = 486662. |
| `fe25519Invert` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` | out = a^(p-2) = 1/a, or 0 when a is 0 (ref10's pow225521 chain: 254 squarings and 11 multiplications, whatever `a` is). |
| `fe25519Pow22523` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` | out = a^((p-5)/8) = a^(2^252 - 3), the exponentiation behind square roots in point decoding (ref10's pow22523 chain). |
| `fe25519CSwap` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | Swap `f` and `g` where `m` is -1; leave both where `m` is 0. `m` must be a mask (`Crypto.Ct`). The Montgomery ladder's conditional swap. |
| `fe25519CMov` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | f = g where `m` is -1; f unchanged where `m` is 0. `m` must be a mask. The table scan's conditional move. |
| `fe25519FromBytes` | value | `(-> Int Int Int)` | `Mut,Unsafe` | out = the 32 little-endian bytes at `p`, with bit 255 ignored. The value may be anything below 2^255, p itself and the 19 values above it included; it is reduced as arithmetic proceeds. |
| `fe25519ToBytes` | value | `(-> Int Int Int)` | `Mut,Unsafe` | Write the canonical 32-byte little-endian encoding of `a` (its value reduced below p) at `p`. `a`'s limbs must be within 1.1 * 2^26 (even) and 1.1 * 2^25 (odd). |
| `fe25519IsNegative` | value | `(-> Int Int)` | `Alloc,Mut,Unsafe` | 1 when `a` is odd once reduced below p, 0 when it is even: the sign of x in an Ed25519 point encoding (RFC 8032, section 5.1.2). |
| `fe25519IsZero` | value | `(-> Int Int)` | `Alloc,Mut,Unsafe` | 1 when `a` is 0 modulo p, 0 otherwise, in time that does not depend on `a`. |

## `Crypto.Ghash`

`stdlib/Crypto/Ghash.ax` — 1 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `ghashUpdate` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` | Absorb `len` bytes at `data` into the running hash at `y` (16 bytes, big-endian, updated in place) under the hash key at `h` (16 bytes): for each 16-byte block X, Y <- (Y xor X) * H in GF(2^128). A final partial block is padded with zeros, so a caller absorbing A and then C gets GCM's padding for each. `len` is public; `y` and `h` are not. |

## `Crypto.Hkdf`

`stdlib/Crypto/Hkdf.ax` — 10 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `hkdfSha256ExpandRaw` | value | `(-> Int Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | HKDF-Expand with HMAC-SHA-256 (section 2.3): `len` bytes to `out` from the `prkLen`-byte key at `prk` and the `infoLen` bytes of info at `info`. T(i) = HMAC(PRK, T(i-1) \| info \| i) for i = 1, 2, ..., and the output is their concatenation cut to `len`. Answers 0. |
| `hkdfSha512ExpandRaw` | value | `(-> Int Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | HKDF-Expand with HMAC-SHA-512: as `hkdfSha256ExpandRaw` with 64-byte blocks. `len` is 1 to 16320. Answers 0. |
| `hkdfSha256Raw` | value | `(-> Int Int Int Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | HKDF with HMAC-SHA-256, extract then expand, by address: `len` bytes to `out`. The pseudorandom key lives only in scratch memory, erased before this returns. Answers 0. |
| `hkdfSha512Raw` | value | `(-> Int Int Int Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | HKDF with HMAC-SHA-512, extract then expand, by address. `len` is 1 to 16320. Answers 0. |
| `hkdfSha256Extract` | value | `(-> String SecretBytes (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | HKDF-Extract with HMAC-SHA-256 (section 2.2): the 32-byte pseudorandom key HMAC(salt, ikm). An empty salt is 32 zero bytes. |
| `hkdfSha256Expand` | value | `(-> SecretBytes String Int (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | HKDF-Expand with HMAC-SHA-256 (section 2.3): `len` bytes from `prk` for the context `info`. `prk` must be at least 32 bytes and `len` 1 to 8160; otherwise `cryptoInvalidLength`. |
| `hkdfSha256` | value | `(-> SecretBytes String String Int (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | HKDF with HMAC-SHA-256: extract from `ikm` with `salt`, then expand `len` bytes for the context `info`. `len` must be 1 to 8160; otherwise `cryptoInvalidLength`. |
| `hkdfSha512Extract` | value | `(-> String SecretBytes (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | HKDF-Extract with HMAC-SHA-512: the 64-byte pseudorandom key HMAC(salt, ikm). An empty salt is 64 zero bytes. |
| `hkdfSha512Expand` | value | `(-> SecretBytes String Int (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | HKDF-Expand with HMAC-SHA-512: `len` bytes from `prk` for the context `info`. `prk` must be at least 64 bytes and `len` 1 to 16320; otherwise `cryptoInvalidLength`. |
| `hkdfSha512` | value | `(-> SecretBytes String String Int (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | HKDF with HMAC-SHA-512: extract from `ikm` with `salt`, then expand `len` bytes for the context `info`. `len` must be 1 to 16320; otherwise `cryptoInvalidLength`. |

## `Crypto.Hmac`

`stdlib/Crypto/Hmac.ax` — 38 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `HmacSha256Key` | struct |  |  | An HMAC-SHA-256 key: a handle to its bytes and their precomputed inner and outer states in the secret store. Prints as `<HmacSha256Key>`. |
| `HmacSha512Key` | struct |  |  | An HMAC-SHA-512 key. Prints as `<HmacSha512Key>`. |
| `hmacSha256KeyGenerate` | value | `(Result HmacSha256Key Error)` | `Alloc,IO,Mut` | A fresh random HMAC-SHA-256 key of 32 bytes, the hash's output length. |
| `hmacSha256KeyFromSecret` | value | `(-> SecretBytes (Result HmacSha256Key Error))` | `Alloc,IO,Mut,Unsafe` | An HMAC-SHA-256 key holding a copy of `s`, which may be any length from 1 byte. This is also the deterministic route for known-answer tests and protocols that derive the key. |
| `hmacSha256KeyExport` | value | `(-> HmacSha256Key (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | The key bytes of `k`, as a new `SecretBytes`. |
| `hmacSha256KeyWipe` | value | `(-> HmacSha256Key Int)` | `Alloc,IO,Mut,Unsafe` | Erase `k` and free its storage. Any later use of `k` stops the program with status 85. Answers 0. |
| `hmacSha512KeyGenerate` | value | `(Result HmacSha512Key Error)` | `Alloc,IO,Mut` | A fresh random HMAC-SHA-512 key of 64 bytes, the hash's output length. |
| `hmacSha512KeyFromSecret` | value | `(-> SecretBytes (Result HmacSha512Key Error))` | `Alloc,IO,Mut,Unsafe` | An HMAC-SHA-512 key holding a copy of `s`, which may be any length from 1 byte. |
| `hmacSha512KeyExport` | value | `(-> HmacSha512Key (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | The key bytes of `k`, as a new `SecretBytes`. |
| `hmacSha512KeyWipe` | value | `(-> HmacSha512Key Int)` | `Alloc,IO,Mut,Unsafe` | Erase `k` and free its storage. Answers 0. |
| `hmacSha256` | value | `(-> HmacSha256Key String String)` | `Alloc,Mut,Unsafe` | The 32-byte HMAC-SHA-256 tag of `msg` under `k`. |
| `hmacSha256Verify` | value | `(-> HmacSha256Key String String Bool)` | `Alloc,Mut,Unsafe` | Whether `tag` is the HMAC-SHA-256 tag of `msg` under `k`. A tag that is not 32 bytes answers false. The comparison takes the same time wherever the tags differ. |
| `hmacSha512` | value | `(-> HmacSha512Key String String)` | `Alloc,Mut,Unsafe` | The 64-byte HMAC-SHA-512 tag of `msg` under `k`. |
| `hmacSha512Verify` | value | `(-> HmacSha512Key String String Bool)` | `Alloc,Mut,Unsafe` | Whether `tag` is the HMAC-SHA-512 tag of `msg` under `k`. A tag that is not 64 bytes answers false. The comparison takes the same time wherever the tags differ. |
| `hmacSha256Raw` | value | `(-> Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | The HMAC-SHA-256 tag under the `keyLen`-byte key at `key` of `n` bytes at `p`, written to the 32 bytes at `out`: the key by address, for Crypto modules holding a key in their own secret memory. Any key length, the empty key included, is used as given. Answers 0. |
| `hmacSha512Raw` | value | `(-> Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | The HMAC-SHA-512 tag under the `keyLen`-byte key at `key` of `n` bytes at `p`, written to the 64 bytes at `out`. Answers 0. |
| `HmacSha256` | struct |  |  | An HMAC-SHA-256 computation in progress. Make one with `hmacSha256New`. |
| `HmacSha512` | struct |  |  | An HMAC-SHA-512 computation in progress. Make one with `hmacSha512New`. |
| `hmacSha256New` | value | `(-> HmacSha256Key HmacSha256)` | `Alloc,Mut,Unsafe` | A streaming HMAC-SHA-256 under `k`. |
| `hmacSha256NewRaw` | value | `(-> Int Int HmacSha256)` | `Alloc,Mut,Unsafe` | A streaming HMAC-SHA-256 under the `keyLen`-byte key at `key`, used as given: the hazardous form for Crypto modules, such as HKDF, that hold a key in their own secret memory. |
| `hmacSha256Chains` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The 64 bytes an HMAC-SHA-256 key precomputes (FIPS 198-1 section 6): the inner chaining value, then the outer one, for the `keyLen`-byte key at `key`, written to `out`. With `hmacSha256NewChains` this lets a Crypto module key many MACs while doing the key schedule once, and keep the key-derived bytes in memory it manages. Answers 0. |
| `hmacSha256NewChains` | value | `(-> Int HmacSha256)` | `Alloc,Mut,Unsafe` | A streaming HMAC-SHA-256 over the 64 precomputed bytes at `chains` that `hmacSha256Chains` wrote. |
| `hmacSha256UpdateAddr` | value | `(-> HmacSha256 Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`. Answers 0, or -1 when `m` is not a live HMAC-SHA-256 state, and then absorbs nothing. |
| `hmacSha256Update` | value | `(-> HmacSha256 String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `m` is not a live HMAC-SHA-256 state. |
| `hmacSha256FinalAddr` | value | `(-> HmacSha256 Int Int)` | `Alloc,Mut,Unsafe` | Write the tag of everything absorbed to the 32 bytes at `out`; `m` is then ready for another message under the same key. Answers 0, or -1 when `m` is not a live HMAC-SHA-256 state. |
| `hmacSha256Final` | value | `(-> HmacSha256 String)` | `Alloc,Mut,Unsafe` | The 32-byte tag of everything absorbed; `m` is then ready for another message under the same key. A value that is not a live HMAC-SHA-256 state answers the empty string. |
| `hmacSha256Copy` | value | `(-> HmacSha256 HmacSha256)` | `Alloc,Mut,Unsafe` | An independent copy of `m`, which goes on from the same point. |
| `hmacSha256Wipe` | value | `(-> HmacSha256 Int)` | `Mut` | Erase everything `m` holds, the key's chaining values included; every later operation on it is refused. Answers 0, or -1 with nothing written when `m` is not a state. |
| `hmacSha512New` | value | `(-> HmacSha512Key HmacSha512)` | `Alloc,Mut,Unsafe` | A streaming HMAC-SHA-512 under `k`. |
| `hmacSha512NewRaw` | value | `(-> Int Int HmacSha512)` | `Alloc,Mut,Unsafe` | A streaming HMAC-SHA-512 under the `keyLen`-byte key at `key`, used as given: the hazardous form for Crypto modules. |
| `hmacSha512Chains` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The 128 bytes an HMAC-SHA-512 key precomputes (FIPS 198-1 section 6): the inner chaining value, then the outer one, for the `keyLen`-byte key at `key`, written to `out`. With `hmacSha512NewChains` this lets a Crypto module key many MACs while doing the key schedule once, and keep the key-derived bytes in memory it manages. Answers 0. |
| `hmacSha512NewChains` | value | `(-> Int HmacSha512)` | `Alloc,Mut,Unsafe` | A streaming HMAC-SHA-512 over the 128 precomputed bytes at `chains` that `hmacSha512Chains` wrote. |
| `hmacSha512UpdateAddr` | value | `(-> HmacSha512 Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`. Answers 0, or -1 when `m` is not a live HMAC-SHA-512 state, and then absorbs nothing. |
| `hmacSha512Update` | value | `(-> HmacSha512 String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `m` is not a live HMAC-SHA-512 state. |
| `hmacSha512FinalAddr` | value | `(-> HmacSha512 Int Int)` | `Alloc,Mut,Unsafe` | Write the tag of everything absorbed to the 64 bytes at `out`; `m` is then ready for another message under the same key. Answers 0, or -1 when `m` is not a live HMAC-SHA-512 state. |
| `hmacSha512Final` | value | `(-> HmacSha512 String)` | `Alloc,Mut,Unsafe` | The 64-byte tag of everything absorbed; `m` is then ready for another message under the same key. A value that is not a live HMAC-SHA-512 state answers the empty string. |
| `hmacSha512Copy` | value | `(-> HmacSha512 HmacSha512)` | `Alloc,Mut,Unsafe` | An independent copy of `m`, which goes on from the same point. |
| `hmacSha512Wipe` | value | `(-> HmacSha512 Int)` | `Mut` | Erase everything `m` holds, the key's chaining values included; every later operation on it is refused. Answers 0, or -1 with nothing written when `m` is not a state. |

## `Crypto.Poly1305`

`stdlib/Crypto/Poly1305.ax` — 6 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `poly1305StateBytes` | value | `Int` |  | The state, 16 words:   words 0-4    r, clamped, in 26-bit limbs   words 5-9    the accumulator h, in 26-bit limbs   words 10-13  s, the key's second half, as 32-bit words   words 14-15  scratch for a padded final block |
| `poly1305Init` | value | `(-> Int Int Int)` | `Mut,Unsafe` | Start a state from the 32-byte one-time key at `key`: r is the first 16 bytes with the clamping of RFC 8439 2.5, s the last 16, and the accumulator zero. |
| `poly1305Blocks` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` | Absorb the `n` whole 16-byte blocks at `p`, each read as a little-endian number plus `hibit` * 2^104 in the top limb: 2^24 for the 2^128 bit every full block carries, 0 for a final block that already has its 0x01 byte. h <- (h + block) * r mod 2^130 - 5, left partly reduced: every limb below 2^26 but the second, which may be slightly above. |
| `poly1305AbsorbPadded` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | Absorb `len` bytes at `p` the way the AEAD of RFC 8439 2.8 does: the whole blocks, then any remainder padded with zeros to 16 bytes and absorbed as a full block (with its 2^128 bit). That padding is `pad16` of the RFC; the standalone MAC pads differently and uses `poly1305Mac`. |
| `poly1305Finish` | value | `(-> Int Int Int)` | `Mut,Unsafe` | Finish: carry the accumulator fully, reduce it below p = 2^130 - 5 with a masked choice between h and h - p, add s modulo 2^128, and write the 16-byte tag at `tag` in little-endian order. The state is wiped. |
| `poly1305Mac` | value | `(-> Int Int Int Int Int Int)` | `Mut,Unsafe` | The Poly1305 tag of the `len` bytes at `msg` under the 32-byte one-time key at `key`, written to the 16 bytes at `tag` (RFC 8439 2.5): whole blocks with their 2^128 bit, then any remainder with a 0x01 byte after it, zero-padded, and no 2^128 bit. `st` is scratch, wiped before this returns. |

## `Crypto.Random`

`stdlib/Crypto/Random.ax` — 9 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `randomFill` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Fill `n` bytes at `p` with secure random bytes. The low-level entry every other function here and every key generator uses. On `Err` the bytes at `p` are unspecified and must not be used. |
| `randomAvailable` | value | `Bool` | `Mut` | Whether this target has a secure entropy source at all. A program can ask before it depends on one. |
| `secureRandomBytes` | value | `(-> Int (Result String Error))` | `Alloc,IO,Mut,Unsafe` | `n` secure random bytes. |
| `randomWord` | value | `(Result Int Error)` | `Alloc,IO,Mut,Unsafe` | A uniformly random 64-bit word (any Int, negative included). |
| `randomBelow` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | A uniformly random Int in 0..bound-1. `bound` must be at least 1. |
| `randomRange` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut` | A uniformly random Int in lo..hi-1. `hi` must be above `lo`, and the range must fit in an Int. |
| `randomShuffle` | value | `(-> (Vec a) (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Shuffle `v` in place into a uniformly random order (Fisher-Yates: position i swaps with a uniform choice among 0..i). Answers `v`'s length. Random words are drawn 32 at a time, so a long vector costs one kernel call per 32 or so positions rather than one each. |
| `randomTokenHex` | value | `(-> Int (Result String Error))` | `Alloc,IO,Mut` | `n` random bytes as lower-case hex (2n characters). |
| `randomTokenUrl` | value | `(-> Int (Result String Error))` | `Alloc,IO,Mut` | `n` random bytes as URL-safe base64 without padding. |

## `Crypto.Secret`

`stdlib/Crypto/Secret.ax` — 17 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `SecretBytes` | struct |  |  | A secret of any length, with no algorithm attached. Algorithms take their own key types, made from one of these with an explicit conversion that checks the length. |
| `secretBlockNew` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | A fresh zeroed secret of `n` payload bytes under handle kind `kind`, as a handle word. |
| `secretBlockAddr` | value | `(-> Int Int Int)` | `Unsafe` | The address of the payload of live secret `h` of kind `kind`. A dead, forged or other-kind handle stops the program with status 85. |
| `secretBlockLen` | value | `(-> Int Int Int)` | `Unsafe` | The payload length of live secret `h`. |
| `secretBlockLocked` | value | `(-> Int Int Bool)` | `Unsafe` | Whether the kernel locked live secret `h` out of swap. |
| `secretBlockFree` | value | `(-> Int Int Int)` | `Alloc,IO,Mut,Unsafe` | Erase and free live secret `h`: zero the whole mapping, unlock it, unmap it, and retire the handle so any later use stops the program. A second free stops it too. Answers 0. |
| `secretBlockFrom` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | A fresh secret of kind `kind` holding a copy of `n` bytes at `p`. |
| `secretBlockRandom` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | A fresh secret of kind `kind` holding `n` random bytes, drawn straight into the mapping so they are never anywhere else. |
| `secretFromString` | value | `(-> String (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | A secret holding a copy of `s`'s bytes. The string itself is not touched: if it held the only other copy, the caller decides whether to overwrite it. |
| `secretRandom` | value | `(-> Int (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | A secret of `n` random bytes from `Crypto.Random`. |
| `secretFromAddr` | value | `(-> Int Int (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | A secret holding a copy of `n` bytes at `p`. For Crypto modules that derive a secret into their own scratch memory and hand it out. |
| `secretLen` | value | `(-> SecretBytes Int)` |  | How many bytes `s` holds. A secret's length is not secret. |
| `secretAddr` | value | `(-> SecretBytes Int)` | `Unsafe` | The payload address of `s`, for a Crypto module reading it. Valid only while `s` stays live. |
| `secretEq` | value | `(-> SecretBytes SecretBytes Bool)` | `Mut,Unsafe` | Whether two secrets hold the same bytes, in time that depends only on their lengths. |
| `secretIsLocked` | value | `(-> SecretBytes Bool)` |  | Whether the kernel locked `s` out of swap. |
| `secretWipe` | value | `(-> SecretBytes Int)` | `Alloc,IO,Mut,Unsafe` | Erase `s` and free its storage. Any later use of `s`, or of a copy of the handle, stops the program with status 85. Answers 0. |
| `secretExposeCopy` | value | `(-> SecretBytes String)` | `Alloc,Mut,Unsafe` | A COPY of the secret's bytes in an ordinary string. This is the one way a secret's value leaves the store, for writing a key to a file you have decided to trust. The copy is arena memory: it is not locked, not wiped by `secretWipe`, and can be printed. Prefer a typed key's own export, which says what the bytes are. |

## `Crypto.Sha2`

`stdlib/Crypto/Sha2.ax` — 39 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Sha256` | struct |  |  | A SHA-256 hash in progress. Make one with `sha256New`. |
| `sha256New` | value | `Sha256` | `Alloc,Mut,Unsafe` | A fresh SHA-256 hash with nothing absorbed. |
| `sha256UpdateAddr` | value | `(-> Sha256 Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`: `sha256Update` for a caller holding raw memory, such as another Crypto module hashing a key in the secret store. Answers 0, or -1 when `h` is not a SHA-256 state or the message would pass the length limit, and then absorbs nothing. |
| `sha256Update` | value | `(-> Sha256 String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `h` is not a SHA-256 state or the message would pass the length limit, and then absorbs nothing. |
| `sha256Final` | value | `(-> Sha256 String)` | `Alloc,Mut,Unsafe` | The 32-byte digest of everything absorbed. `h` is then reset to a fresh hash, its partial block wiped, ready for another message. A value that is not a SHA-256 state answers the empty string. |
| `sha256Copy` | value | `(-> Sha256 Sha256)` | `Alloc,Mut,Unsafe` | An independent copy of `h`, which goes on from the same point. Prime one state with a shared prefix, then copy it once per message. |
| `sha256Wipe` | value | `(-> Sha256 Int)` | `Mut,Unsafe` | Erase everything `h` holds and leave it a fresh hash. Answers 0, or -1 with nothing written when `h` is not a SHA-256 state. |
| `sha256Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The SHA-256 digest of `n` bytes at `p`, written to the 32 bytes at `out`. Answers 0. The scratch state is wiped before it returns. |
| `sha256` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 32-byte SHA-256 digest of `msg`. |
| `Sha512` | struct |  |  | A SHA-512 hash in progress. Make one with `sha512New`. |
| `Sha384` | struct |  |  | A SHA-384 hash in progress. Make one with `sha384New`. |
| `sha512New` | value | `Sha512` | `Alloc,Mut,Unsafe` | A fresh SHA-512 hash with nothing absorbed. |
| `sha512UpdateAddr` | value | `(-> Sha512 Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`. Answers 0, or -1 when `h` is not a SHA-512 state or the message would pass the length limit, and then absorbs nothing. |
| `sha512Update` | value | `(-> Sha512 String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `h` is not a SHA-512 state or the message would pass the length limit, and then absorbs nothing. |
| `sha512Final` | value | `(-> Sha512 String)` | `Alloc,Mut,Unsafe` | The 64-byte digest of everything absorbed. `h` is then reset to a fresh hash, its partial block wiped. A value that is not a SHA-512 state answers the empty string. |
| `sha512Copy` | value | `(-> Sha512 Sha512)` | `Alloc,Mut,Unsafe` | An independent copy of `h`, which goes on from the same point. |
| `sha512Wipe` | value | `(-> Sha512 Int)` | `Mut,Unsafe` | Erase everything `h` holds and leave it a fresh hash. Answers 0, or -1 with nothing written when `h` is not a SHA-512 state. |
| `sha512Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The SHA-512 digest of `n` bytes at `p`, written to the 64 bytes at `out`. Answers 0. The scratch state is wiped before it returns. |
| `sha512` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 64-byte SHA-512 digest of `msg`. |
| `sha384New` | value | `Sha384` | `Alloc,Mut,Unsafe` | A fresh SHA-384 hash with nothing absorbed. |
| `sha384UpdateAddr` | value | `(-> Sha384 Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`. Answers 0, or -1 when `h` is not a SHA-384 state or the message would pass the length limit, and then absorbs nothing. |
| `sha384Update` | value | `(-> Sha384 String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `h` is not a SHA-384 state or the message would pass the length limit, and then absorbs nothing. |
| `sha384Final` | value | `(-> Sha384 String)` | `Alloc,Mut,Unsafe` | The 48-byte digest of everything absorbed. `h` is then reset to a fresh hash, its partial block wiped. A value that is not a SHA-384 state answers the empty string. |
| `sha384Copy` | value | `(-> Sha384 Sha384)` | `Alloc,Mut,Unsafe` | An independent copy of `h`, which goes on from the same point. |
| `sha384Wipe` | value | `(-> Sha384 Int)` | `Mut,Unsafe` | Erase everything `h` holds and leave it a fresh hash. Answers 0, or -1 with nothing written when `h` is not a SHA-384 state. |
| `sha384Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The SHA-384 digest of `n` bytes at `p`, written to the 48 bytes at `out`. Answers 0. The scratch state is wiped before it returns. |
| `sha384` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 48-byte SHA-384 digest of `msg`. |
| `sha256RawSize` | value | `Int` |  | The bytes a raw SHA-256 state occupies. |
| `sha256RawInit` | value | `(-> Int Int)` | `Mut,Unsafe` | Make the `sha256RawSize` bytes at `st` a fresh SHA-256 state. Answers 0. |
| `sha256RawUpdate` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at `p` into the raw state at `st`. Answers 0, or -1 past the length limit, and then absorbs nothing. |
| `sha256RawFinal` | value | `(-> Int Int Int)` | `Mut,Unsafe` | Write the digest of the raw state at `st` to the 32 bytes at `out`, then reset the state to a fresh one. Answers 0. |
| `sha256RawResume` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | Make the raw state at `st` one that has absorbed `count` bytes and holds the chaining value in the 32 bytes at `chain`, most significant byte of each word first: the state `sha256RawChain` saved. `count` must be a multiple of 64. Answers 0. |
| `sha256RawChain` | value | `(-> Int Int Int)` | `Mut,Unsafe` | Write the chaining value of the raw state at `st` to the 32 bytes at `out`, most significant byte of each word first. Meaningful only after a whole number of blocks; answers 0, or -1 with nothing written when a partial block is waiting. |
| `sha512RawSize` | value | `Int` |  | The bytes a raw SHA-512 or SHA-384 state occupies. |
| `sha512RawInit` | value | `(-> Int Int)` | `Mut,Unsafe` | Make the `sha512RawSize` bytes at `st` a fresh SHA-512 state. Answers 0. |
| `sha512RawUpdate` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at `p` into the raw SHA-512 or SHA-384 state at `st`. Answers 0, or -1 past the length limit, and then absorbs nothing. |
| `sha512RawFinal` | value | `(-> Int Int Int)` | `Mut,Unsafe` | Write the SHA-512 digest of the raw state at `st` to the 64 bytes at `out`, then reset the state to a fresh SHA-512 one. Answers 0. |
| `sha512RawResume` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | Make the raw state at `st` one that has absorbed `count` bytes and holds the chaining value in the 64 bytes at `chain`, most significant byte of each word first. `count` must be a multiple of 128. Answers 0. |
| `sha512RawChain` | value | `(-> Int Int Int)` | `Mut,Unsafe` | Write the chaining value of the raw SHA-512 state at `st` to the 64 bytes at `out`, most significant byte of each word first. Answers 0, or -1 with nothing written when a partial block is waiting. |

## `Crypto.Sha3`

`stdlib/Crypto/Sha3.ax` — 39 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `keccakF1600` | value | `(-> Int Int)` | `Mut,Unsafe` | Keccak-f[1600], Algorithm 7 with 24 rounds, on the 25 lanes at `st`: lane (x, y) in word x + 5y, as a 64-bit word. On a little-endian machine that is also FIPS 202's byte order for the state. |
| `sha3_224Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The SHA3-224 digest of `n` bytes at `p`, written to the 28 bytes at `out`. Answers 0. |
| `sha3_256Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The SHA3-256 digest of `n` bytes at `p`, written to the 32 bytes at `out`. Answers 0. |
| `sha3_384Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The SHA3-384 digest of `n` bytes at `p`, written to the 48 bytes at `out`. Answers 0. |
| `sha3_512Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | The SHA3-512 digest of `n` bytes at `p`, written to the 64 bytes at `out`. Answers 0. |
| `sha3_224` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 28-byte SHA3-224 digest of `msg`. |
| `sha3_256` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 32-byte SHA3-256 digest of `msg`. |
| `sha3_384` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 48-byte SHA3-384 digest of `msg`. |
| `sha3_512` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | The 64-byte SHA3-512 digest of `msg`. |
| `Sha3` | struct |  |  | A SHA-3 hash in progress, of any of the four sizes. Make one with `sha3_224New`, `sha3_256New`, `sha3_384New` or `sha3_512New`. |
| `sha3_224New` | value | `Sha3` | `Alloc,Mut` | A fresh SHA3-224 hash. |
| `sha3_256New` | value | `Sha3` | `Alloc,Mut` | A fresh SHA3-256 hash. |
| `sha3_384New` | value | `Sha3` | `Alloc,Mut` | A fresh SHA3-384 hash. |
| `sha3_512New` | value | `Sha3` | `Alloc,Mut` | A fresh SHA3-512 hash. |
| `sha3UpdateAddr` | value | `(-> Sha3 Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`. Answers 0, or -1 when `h` is not a SHA-3 state, and then absorbs nothing. |
| `sha3Update` | value | `(-> Sha3 String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `h` is not a SHA-3 state. |
| `sha3Final` | value | `(-> Sha3 String)` | `Alloc,Mut,Unsafe` | The digest of everything absorbed: 28, 32, 48 or 64 bytes, as `h` was made. `h` is then reset to a fresh hash of the same size. A value that is not a SHA-3 state answers the empty string. |
| `sha3Copy` | value | `(-> Sha3 Sha3)` | `Alloc,Mut,Unsafe` | An independent copy of `h`, which goes on from the same point. |
| `sha3Wipe` | value | `(-> Sha3 Int)` | `Mut,Unsafe` | Erase everything `h` holds and leave it a fresh hash of the same size. Answers 0, or -1 with nothing written when `h` is not a SHA-3 state. |
| `shake128Addr` | value | `(-> Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | `outLen` bytes of SHAKE128 over `n` bytes at `p`, written to `out`. Answers 0. |
| `shake256Addr` | value | `(-> Int Int Int Int Int)` | `Alloc,Mut,Unsafe` | `outLen` bytes of SHAKE256 over `n` bytes at `p`, written to `out`. Answers 0. |
| `shake128` | value | `(-> String Int String)` | `Alloc,Mut,Unsafe` | The first `outLen` bytes of SHAKE128 over `msg`. A negative length answers the empty string. |
| `shake256` | value | `(-> String Int String)` | `Alloc,Mut,Unsafe` | The first `outLen` bytes of SHAKE256 over `msg`. A negative length answers the empty string. |
| `Shake128` | struct |  |  | A SHAKE128 extendable-output function in progress: absorb input, then squeeze output in as many pieces as wanted. |
| `Shake256` | struct |  |  | A SHAKE256 extendable-output function in progress. |
| `shake128New` | value | `Shake128` | `Alloc,Mut` | A fresh SHAKE128 with nothing absorbed. |
| `shake256New` | value | `Shake256` | `Alloc,Mut` | A fresh SHAKE256 with nothing absorbed. |
| `shake128AbsorbAddr` | value | `(-> Shake128 Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`. Answers 0, or -1 when `x` is not a SHAKE128 state or has begun squeezing, and then absorbs nothing. |
| `shake128Absorb` | value | `(-> Shake128 String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `x` is not a SHAKE128 state or has begun squeezing. |
| `shake128SqueezeAddr` | value | `(-> Shake128 Int Int Int)` | `Mut,Unsafe` | Squeeze the next `n` bytes of output to address `out`; the first squeeze ends the input. Answers 0, or -1 when `x` is not a SHAKE128 state or `n` is negative. |
| `shake128Squeeze` | value | `(-> Shake128 Int String)` | `Alloc,Mut,Unsafe` | The next `n` bytes of output; the first squeeze ends the input. A negative `n`, or a value that is not a SHAKE128 state, answers the empty string. |
| `shake128Copy` | value | `(-> Shake128 Shake128)` | `Alloc,Mut,Unsafe` | An independent copy of `x`, which goes on from the same point. |
| `shake128Wipe` | value | `(-> Shake128 Int)` | `Mut,Unsafe` | Erase everything `x` holds and leave it a fresh SHAKE128. Answers 0, or -1 with nothing written when `x` is not a sponge state. |
| `shake256AbsorbAddr` | value | `(-> Shake256 Int Int Int)` | `Mut,Unsafe` | Absorb `n` bytes at address `p`. Answers 0, or -1 when `x` is not a SHAKE256 state or has begun squeezing, and then absorbs nothing. |
| `shake256Absorb` | value | `(-> Shake256 String Int)` | `Mut,Unsafe` | Absorb `msg`. Answers 0, or -1 when `x` is not a SHAKE256 state or has begun squeezing. |
| `shake256SqueezeAddr` | value | `(-> Shake256 Int Int Int)` | `Mut,Unsafe` | Squeeze the next `n` bytes of output to address `out`; the first squeeze ends the input. Answers 0, or -1 when `x` is not a SHAKE256 state or `n` is negative. |
| `shake256Squeeze` | value | `(-> Shake256 Int String)` | `Alloc,Mut,Unsafe` | The next `n` bytes of output; the first squeeze ends the input. A negative `n`, or a value that is not a SHAKE256 state, answers the empty string. |
| `shake256Copy` | value | `(-> Shake256 Shake256)` | `Alloc,Mut,Unsafe` | An independent copy of `x`, which goes on from the same point. |
| `shake256Wipe` | value | `(-> Shake256 Int)` | `Mut,Unsafe` | Erase everything `x` holds and leave it a fresh SHAKE256. Answers 0, or -1 with nothing written when `x` is not a sponge state. |

## `Crypto.X25519`

`stdlib/Crypto/X25519.ax` — 13 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `X25519SecretKey` | struct |  |  | An X25519 private key: a handle to 32 secret bytes and their public key in the secret store. Prints as `<X25519SecretKey>`. |
| `X25519PublicKey` | struct |  |  | An X25519 public key: a u-coordinate, 32 little-endian bytes. Build one with `x25519PublicKeyFromBytes`. |
| `x25519ScalarMultAddr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | X25519(k, u) at raw addresses: write the u-coordinate of [k]u at `out`, where `k` is clamped first and bit 255 of `u` is ignored. No all-zero check. Both inputs are read before `out` is written, so `out` may be either of them. |
| `x25519ScalarMult` | value | `(-> String String (Result String Error))` | `Alloc,Mut,Unsafe` | X25519(k, u) on byte strings: the raw function of RFC 7748, section 5, with no all-zero check. `Err` with `cryptoInvalidLength` unless both are 32 bytes. For known-answer tests and protocols that specify the raw function; key agreement wants `x25519`. |
| `x25519BasePoint` | value | `String` | `Alloc,Mut,Unsafe` | The u-coordinate of the base point, 9, as 32 bytes. |
| `x25519KeyGenerate` | value | `(Result X25519SecretKey Error)` | `Alloc,IO,Mut,Unsafe` | A fresh random private key and its public key. |
| `x25519KeyFromSecret` | value | `(-> SecretBytes (Result X25519SecretKey Error))` | `Alloc,IO,Mut,Unsafe` | The private key held in `s`, which must be 32 bytes, and its public key. `s` is copied, not consumed. Any 32 bytes are a private key (RFC 7748 clamps them when they are used), so this is also the deterministic route for known-answer tests and for protocols that derive the key themselves. |
| `x25519KeyWipe` | value | `(-> X25519SecretKey Int)` | `Alloc,IO,Mut,Unsafe` | Erase `k` and free its storage. Any later use of `k` stops the program with status 85. Answers 0. |
| `x25519KeyExport` | value | `(-> X25519SecretKey (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | The 32 private-key bytes of `k`, as a new `SecretBytes`: the standard serialisation (RFC 7748, section 5), for storing the key somewhere you trust. |
| `x25519PublicKey` | value | `(-> X25519SecretKey X25519PublicKey)` | `Alloc,Mut,Unsafe` | The public key of `k`. |
| `x25519PublicKeyFromBytes` | value | `(-> String (Result X25519PublicKey Error))` | `Alloc,Mut` | A public key from its 32 bytes. Every 32-byte string is accepted (RFC 7748, section 5); any other length is `cryptoInvalidLength`. |
| `x25519PublicKeyBytes` | value | `(-> X25519PublicKey String)` |  | The 32 bytes of a public key. |
| `x25519` | value | `(-> X25519SecretKey X25519PublicKey (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` | The shared secret X25519(k, pk), as `SecretBytes`. `Err` with `cryptoInvalidKey` when it is all zero (the peer sent a point of small order), and `cryptoInvalidLength` when `pk` is not 32 bytes. |

## `Err`

`stdlib/Err.ax` — 36 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Result` | data |  |  |  |
| `Error` | struct |  |  |  |
| `errDivideByZero` | value | `Int` |  | The codes this module raises itself. A program's own codes live in its own space; these are the ones `ERR-REC-2` needs. |
| `errOverflow` | value | `Int` |  |  |
| `errShiftTooWide` | value | `Int` |  |  |
| `errShortWrite` | value | `Int` |  | A descriptor accepted some bytes and then accepted none, without an errno to say why. It is NOT a syscall error - `write` returned 0, which is a legal answer - so it cannot borrow an errno, and it is not success either, which is exactly why `Sys.sysWriteAllFd` could not express it while it answered an Int. `ERR-REC-3` calls a short write a failure and not an absence: the bytes were meant to go and did not. |
| `mkError` | value | `(-> Int String Error)` | `Alloc` |  |
| `errCode` | value | `(-> Error Int)` |  |  |
| `errMessage` | value | `(-> Error String)` |  |  |
| `errContext` | value | `(-> Error String)` |  |  |
| `errorText` | value | `(-> Error String)` | `Alloc,Mut` | The rendering `main` writes to fd 2 (ERR-REC-4), and the one a program builds a longer report out of. A plain function rather than a format hole: a rendering is chosen from a concrete type, so a value reached through a type variable is AX3025, and every caller here has a concrete `Error` in hand anyway. |
| `isOk` | value | `(-> (Result a e) Bool)` |  |  |
| `isErr` | value | `(-> (Result a e) Bool)` |  |  |
| `unwrapOr` | value | `(-> (Result a e) a a)` |  |  |
| `mapOk` | value | `(-> (Result a e) (-> a b) (Result b e))` | `Alloc` |  |
| `mapErr` | value | `(-> (Result a e) (-> e f) (Result a f))` | `Alloc` |  |
| `andThen` | value | `(-> (Result a e) (-> a (Result b e)) (Result b e))` | `Alloc` |  |
| `errContextOf` | value | `(-> Error String Error)` | `Alloc` | Attach what the caller was doing to an error in flight, passing `Ok` through untouched. It needs no binder, so it is a function and not a form. |
| `withContext` | value | `(-> (Result a Error) String (Result a Error))` | `Alloc` |  |
| `okOr` | value | `(-> (Option a) e (Result a e))` | `Alloc` |  |
| `toOption` | value | `(-> (Result a e) (Option a))` | `Alloc` |  |
| `isSome` | value | `(-> (Option a) Bool)` |  | Whether the `Option` holds a value. The `Option` half of `isOk`. |
| `isNone` | value | `(-> (Option a) Bool)` |  | Whether the `Option` is empty. Exactly `isSome` negated, spelled out because a caller reads for the case it cares about. |
| `optUnwrapOr` | value | `(-> (Option a) a a)` |  | The value, or `fallback` when there is none. The one combinator that ends the `Option` rather than passing it on, and the reason most call sites need no `match` at all. |
| `optMap` | value | `(-> (Option a) (-> a b) (Option b))` | `Alloc` | Apply `f` to the value if there is one, leaving an absence alone. The result type is `f`'s, so this is how an `(Option Int)` becomes an `(Option String)`. |
| `optAndThen` | value | `(-> (Option a) (-> a (Option b)) (Option b))` |  | Chain a step that may itself be absent, without nesting two `Option`s. `optMap` with a function answering `(Option b)` would give `(Option (Option b))`; this is that flattened. |
| `optOr` | value | `(-> (Option a) (Option a) (Option a))` | `Alloc` | The first of two that is present. `alt` is EVALUATED at the call, so this is not a short-circuit: a caller whose alternative is expensive should write the `match`. Said here because the name is borrowed from languages where it is lazy. |
| `intMin` | value | `Int` |  |  |
| `addChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` | The three that WRAP. |
| `subChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `mulChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `divChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `remChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `shlChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` | A shift amount of 64 or more, and a negative one, are undefined and no masking is emitted - `(<< 1 100)` answers 68719476736 at `--opt 0` and 1 at `--opt 1`. |
| `shrChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  |
| `try!` | macro |  |  | ERR-SUGAR-2: the propagation form. |

## `Fallible`

`stdlib/Fallible.ax` — 9 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Fallible` | effect |  |  | Fallible - the effect a batch loop's deep callee performs on a malformed record, and the handlers that answer it without unwinding. |
| `fallibleSkipped` | value | `Int` |  | The value a handler answers to mean "skip this record": the most negative `Int`. A loop compares the value it got against this, or asks `fallibleIsSkipped`. |
| `fallibleIsSkipped` | value | `(-> Int Bool)` |  | Whether a value is the skip sentinel. The comparison a batch loop makes once per record; it allocates nothing. |
| `fallibleSkip` | value | `(-> String Int)` |  | Skip every malformed record: answer `fallibleSkipped`, whatever the message. A one-parameter top-level function is a value, so it is passed bare. |
| `fallibleDefault` | value | `(-> Int String Int)` |  | Use `d` in place of every malformed record. Built ONCE, at the `handle`, which is why the fallback is here and not an argument of the operation: the closure holding `d` is allocated when the handler is installed, not when a record is bad. One parameter, answering the handler - the type is spelled flat because every function type is curried and that is the formatter's normal form; `mkAdder` in `280-function-application.ax` is the precedent. |
| `FallibleTally` | struct |  |  | How many records were malformed. A struct rather than a bare `Int` because the handler has to write it from inside a closure, and a field store is the one mutation visible through every holder of the value (reference.md, Built-in Effects: `Mut`). |
| `fallibleTally` | value | `FallibleTally` | `Alloc` | A fresh tally at zero. |
| `fallibleCount` | value | `(-> FallibleTally Int)` |  | What a tally holds. |
| `fallibleCounting` | value | `(-> FallibleTally (-> String Int) String Int)` | `Mut` | Count every malformed record in `tally`, then answer as `next` would: `(fallibleCounting t fallibleSkip)` skips and counts, `(fallibleCounting t (fallibleDefault 0))` substitutes and counts. The `handle` installing it lists `Mut` beside `Fallible`, because a handler's own effects count at the site that installs it. |

## `Ffi`

`stdlib/Ffi.ax` — 16 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `ffiStatusOk` | value | `Int` |  |  |
| `ffiStatusErr` | value | `Int` |  |  |
| `ffiStatusNone` | value | `Int` |  |  |
| `ffiHandleNew` | value | `(-> Int Int Handle)` | `Alloc,Mut,Unsafe` | A fresh Handle over `ptr`, to be destroyed by the C function at `dropFn` (`i64 (i64)`). The block is born free-floating and adopted by this function's own answer (event 2), exactly as `strWrapOwned` adopts a header - so the caller holds one share. |
| `ffiHandlePtr` | value | `(-> Handle Int)` | `Unsafe` | The Rust pointer, 0 once the handle is closed. |
| `ffiHandleLive` | value | `(-> Handle Bool)` |  |  |
| `ffiHandleClose` | value | `(-> Handle Int)` | `Mut,Unsafe` | Destroy the Rust value NOW, once: the destructor runs and the pointer is zeroed, so a second close and the handle's own death do nothing. |
| `ffiCellNew` | value | `Int` | `Alloc` | A two-word out-cell, zeroed, held by one share the wrapper gives back with `ffiCellFree`. |
| `ffiCellNewN` | value | `(-> Int Int)` | `Alloc,Unsafe` | An out-cell of `n` words (at least two: a status' message is `{ptr, len}`), for a record that crosses as its fields (one word each, in declaration order) or any payload wider than two words. |
| `ffiWordAt` | value | `(-> Int Int Int)` | `Unsafe` | Word `i` of a Rust-owned word buffer: what a generated wrapper reads a record's fields or a list's lengths through before freeing it. The same read as `ffiCellWord`, kept under its own name because the two describe different things to a reader of the generated module - one is Rust's buffer, one is the cell the wrapper allocated - and written in terms of it so there is one load. |
| `ffiCellFree` | value | `(-> Int Int)` | `Unsafe` | Release the share returned by ffiCellNew/ffiCellNewN exactly once. `c` must be that live cell, with no outstanding foreign use of it. |
| `ffiCellWord` | value | `(-> Int Int Int)` | `Unsafe` |  |
| `ffiBytesToStr` | value | `(-> Int Int String)` | `Alloc,Mut,Unsafe` | Rust-owned bytes copied into a fresh Axiom `String`. `strAlloc` reserves len+1 and zeroes it, so the NUL terminator is already there. Does NOT free the Rust side: the wrapper calls `ffiFreeBytes` after. |
| `ffiWordsToVec` | value | `(-> Int Int (Vec Int))` | `Alloc,Mut,Unsafe` | A Rust `Vec<i64>` copied into an Axiom `Vec`: `p` points at `n` words. Does NOT free the Rust side: the wrapper calls `ffiFreeWords`. |
| `ffiStrsToVec` | value | `(-> Int Int (Vec String))` | `Alloc,Mut,Unsafe` | A Rust `Vec<String>` copied into an Axiom `Vec` of Strings: `p` points at `2n` words, `{bytesPtr, byteLen}` per element. Does NOT free the Rust side: the wrapper calls `ffiFreeStrList`. |
| `ffiWordListsToVec` | value | `(-> Int Int (Vec (Vec Int)))` | `Alloc,Mut,Unsafe` | A Rust `Vec<Vec<T>>` of word scalars copied into an Axiom `Vec` of `Vec`s: `p` points at `2n` words, `{wordsPtr, len}` per inner list. Does NOT free the Rust side: the wrapper calls `ffiFreeWordLists`. |

## `Float`

`stdlib/Float.ax` — 10 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `floatToBits` | value | `(-> Float Int)` |  | The bits of `x`, sign first: the IEEE 754 binary64 encoding read as an `Int`. `(floatToBits 1.0)` is 4607182418800017408 and `(floatToBits -0.0)` is the most negative `Int`. |
| `floatFromBits` | value | `(-> Int Float)` |  | The `Float` whose IEEE 754 binary64 encoding is `n`. Every `Int` is some `Float`, including the infinities and every NaN payload. |
| `floatInfinity` | value | `Float` |  | Positive infinity. |
| `floatNan` | value | `Float` |  | The quiet NaN `floatParse` answers for "nan". |
| `floatIsNan` | value | `(-> Float Bool)` |  | True for every NaN, whatever its sign and payload. |
| `floatIsInfinite` | value | `(-> Float Bool)` |  | True for positive and negative infinity. |
| `floatIsFinite` | value | `(-> Float Bool)` |  | True for every value that is neither an infinity nor a NaN. |
| `floatParseFailed` | value | `Int` |  | Text that isn't a number `floatParse` reads. |
| `floatParse` | value | `(-> String (Result Float Error))` | `Alloc,Mut,Unsafe` | The number that `s` spells, correctly rounded to the nearest binary64, ties to even. See the module comment for the syntax. |
| `floatToString` | value | `(-> Float String)` | `Alloc,Mut,Unsafe` | The shortest text that `floatParse` reads back to exactly `x`, in Python's `repr` format: `0.1`, `2.0`, `1e+22`, `-0.0`, `inf`, `nan`. |

## `Fmt`

`stdlib/Fmt.ax` — 10 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `fmtIntWidth` | value | `(-> Int Int)` |  | Decimal digits in `n`, counting a leading `-` and treating 0 as one digit. |
| `fmtInt` | value | `(-> Int String)` | `Alloc,Mut` | `n` in base 10 as a `Str`. |
| `fmtHex` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` |  |
| `fmtPadLeft` | value | `(-> String Int String)` | `Alloc,Mut,Unsafe` | `s` padded on the left with spaces to at least `width` bytes. |
| `fmtPadRight` | value | `(-> String Int String)` | `Alloc,Mut,Unsafe` | `s` padded on the right with spaces to at least `width` bytes. |
| `fmtPadCenter` | value | `(-> String Int String)` | `Alloc,Mut,Unsafe` | `s` centred in `width` bytes. An odd remainder goes to the RIGHT, which is the convention Rust's `{:^}` uses and the one that makes a column of centred labels line up with a left-aligned header. |
| `fmtPadZerosLeft` | value | `(-> String Int String)` | `Alloc,Mut,Unsafe` | `s` padded on the left with ZEROS to at least `width` bytes, with a leading sign kept in front of them: `-7` at width 4 is `-007` and not `00-7`. That is the whole reason this is not `fmtPadLeft` with a different byte, and it is why the format specifier `{n:04}` can be one call rather than a sign test at every call site. |
| `fmtHexUpper` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | Uppercase hexadecimal, for the `{n:X}` specifier. Same digits as `fmtHex`, and deliberately a separate function rather than a flag: the specifier picks one at expansion time, so a branch would be a runtime test of a compile-time constant. |
| `fmtFloat` | value | `(-> Float String)` | `Alloc,Mut` | `x` with six decimal places. |
| `fmtFloatPrec` | value | `(-> Float Int String)` | `Alloc,Mut` | `x` with `places` decimal places, rounded half away from zero. |

## `IO`

`stdlib/IO.ax` — 38 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `writeStr` | value | `(-> Int String Int)` | `Alloc,IO,Unsafe` | Write all of `s` to `fd`, returning the number of bytes written or a negative errno. |
| `writeSlice` | value | `(-> Int String Int Int Int)` | `Alloc,IO,Unsafe` | Write the `len` bytes of `s` that start at byte `start`, all of them, returning the number written or a negative errno - `writeStr` over a part of a string, with no copy. |
| `printlnLit` | value | `(-> Int Int)` | `Alloc,IO,Unsafe` |  |
| `println` | macro |  |  |  |
| `eprintln` | macro |  |  |  |
| `readFileLit` | value | `(-> Int String)` | `Alloc,IO,Mut,Unsafe` | The whole contents of the file at NUL-terminated path `cstr`, or an empty `Str` if it cannot be opened. |
| `readFile` | value | `(-> String String)` | `Alloc,IO,Mut,Unsafe` |  |
| `ioResult` | value | `(-> (Result Int Error) String String (Result Int Error))` | `Alloc,Mut` | A `Sys` answer re-wrapped with the path this layer knows. |
| `writeFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Write `s` to `path`, creating it or TRUNCATING what is there. Answers `(Ok bytes)`, or `(Err e)` whose code is the errno. |
| `appendFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Add `s` to the end of `path`, creating it if absent. Answers the `(Ok bytes)`, or `(Err e)` whose code is the errno. |
| `removeFile` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Remove the file `path`. Answers 0, or a negative errno. |
| `renamePath` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Move `old` to `new`, answering 0 or a negative errno. |
| `openPath` | value | `(-> String Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Open `path` with `flags` (`oRdonly`, `oWronlyCreateTrunc`, ...): `(Ok fd)`, or `(Err e)` whose code is the errno. New files get mode 0644. The descriptor is the caller's to close with `sysCloseFd`. |
| `openBeneath` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Open `rel` for reading inside the directory `root`, following no symbolic link below it: `(Ok fd)`, or `(Err e)`. `rel` must be relative, with no `..` segment; see `Sys.sysOpenBeneath` for the rules and why it walks one segment at a time. |
| `makeSymlink` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Create the symbolic link `link` whose content is `target`. Answers `(Ok 0)`, or `(Err e)` - EEXIST when `link` is already there. |
| `copyFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` | Copy `src` onto `dst`, answering `(Ok bytes)` or `(Err e)`. `dst` is created or truncated. |
| `fileExists` | value | `(-> String Bool)` | `Alloc,IO,Mut,Unsafe` | True when `path` names something that can be opened for reading - a directory included. `isDir` separates them. |
| `isDir` | value | `(-> String Bool)` | `Alloc,IO,Mut,Unsafe` | True when `path` names a directory. |
| `fileSize` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | The size of `path` in bytes, or a negative errno. |
| `readErrno` | value | `(-> String Int)` | `Alloc,IO,Mut,Unsafe` | 0 when `path` can be read as a file, otherwise the errno saying why not: 2 missing, 13 not permitted, 21 a directory. |
| `makeDir` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Create the directory `path`, mode 0755. Answers 0, or a negative errno - `-17` (EEXIST) when it is already there. |
| `makeDirMode` | value | `(-> String Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Create the directory `path` with the permission bits `mode`, such as 448 (0700) for a directory only its owner may enter. Answers `(Ok 0)`, or `(Err e)`. |
| `makeDirAll` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` | Create `path` and every missing directory above it. Answers 0, or the negative errno of the first component that could not be made. |
| `removeDir` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Remove the EMPTY directory `path`. Answers 0, or a negative errno - `-66`/`-39` (ENOTEMPTY) when it still holds entries. Nothing here removes a tree: that is a loop over `listDir`, and it is the caller's to write, because a library that deletes recursively on one call is a library that deletes the wrong subtree once. |
| `listDir` | value | `(-> String (Vec String))` | `Alloc,IO,Mut,Unsafe` | The entries of the directory `path`, as a Vec of `Str` - sorted by byte, with `.` and `..` removed. |
| `cwd` | value | `(Result String Error)` | `Alloc,IO,Mut` | The process's working directory as an absolute path: `(Ok path)`, or `(Err e)` whose code is the errno. See `Sys.sysGetCwd` for why this is two different syscalls underneath, and why it stopped answering `""` for every distinct reason it can fail. |
| `exit` | value | `(-> Int Int)` | `IO` |  |
| `die` | value | `(-> String Int Int)` | `Alloc,IO,Mut` | Print `s` to standard error and exit with `code`. Never returns. |
| `todo` | value | `(-> String a)` | `Alloc,IO,Mut` | Exit 70 with `todo: <what>` on standard error; types as any result and never returns. |
| `readLine` | value | `(-> Int (Result (Option String) Error))` | `Alloc,IO,Mut` | One line of `fd` without its newline: `(Ok (Some line))`; `(Ok None)` at end of input when nothing was read; `(Err e)` whose code is the errno, its message `readLine: fd 0: errno 9`. |
| `readAll` | value | `(-> Int (Result String Error))` | `Alloc,IO,Mut` | Everything left on `fd` to end of input: `(Ok s)`, `(Ok "")` when nothing arrived, or `(Err e)` whose code is the errno. |
| `readInto` | value | `(-> Int String Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | One `read(2)` of at most `count` bytes from `fd` into the bytes of `buf` that start at byte `at`: `(Ok n)` with `n` the bytes read, `(Ok 0)` at end of input, or `(Err e)` whose code is the errno. |
| `randomBytes` | value | `(-> Int (Result String Error))` | `Alloc,IO,Mut,Unsafe` | `n` bytes of kernel entropy as a fresh string: `(Ok bytes)`, or `(Err e)` whose code is the errno. The bytes are for keys, nonces and seeds; `strByte` reads them one at a time. A negative `n` stops the program with status 77. |
| `TermSize` | struct |  |  | A terminal's size in character cells. A terminal that was never sized reports 0 for both; treat 0 as unknown and fall back to 80x24. |
| `termSave` | value | `(-> Int (Result TermState Error))` | `Alloc,IO,Unsafe` | The attributes of the terminal on `fd`, saved: `(Ok state)` to hand to `termRestore` later, or `(Err e)` - ENOTTY when `fd` is not a terminal. |
| `termRaw` | value | `(-> Int Bool (Result TermState Error))` | `Alloc,IO,Mut,Unsafe` | Put the terminal on `fd` into raw mode, saving what it was first: `(Ok state)` to restore it with, or `(Err e)`. With `keepSignals` true, ^C still raises SIGINT; see `Sys.sysTermRaw` for every flag raw mode changes. |
| `termRestore` | value | `(-> TermState (Result Int Error))` | `Alloc,IO,Unsafe` | Put back the attributes `st` saved, on the descriptor they came from: `(Ok 0)`, or `(Err e)`. |
| `termSize` | value | `(-> Int (Result TermSize Error))` | `Alloc,IO,Unsafe` | The size of the terminal on `fd`: `(Ok size)`, or `(Err e)` - ENOTTY when `fd` is not a terminal. |

## `Intern`

`stdlib/Intern.ax` — 9 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `internSlotOf` | value | `(-> String Int Int)` |  | The slot `s` probes first, in [0, cap). |
| `internNew` | value | `Int` | `Alloc,Mut` | `internDefaultCap` is a *slot* count, so it is passed straight to `internAllocTable` and not through `internWithCapacity`, which takes a *string* count and doubles it. Routing it through the latter would make a fresh interner 128 slots while its own documentation said 64. |
| `internWithCapacity` | value | `(-> Int Int)` | `Alloc,Mut` | An interner sized so `want` distinct strings fit without rehashing. |
| `internFree` | value | `(-> Int Int)` | `Unsafe` | Hand `it` back: the slot table, the `Vec`, and one share of every string in it. Answers 0, as `Vec.vecFree` and `Map.mapFree` do. `it` must be a live interner owning this share. Its raw Int handle and any unretained views into it must not be used after release. |
| `internCap` | value | `(-> Int Int)` | `Unsafe` |  |
| `internCount` | value | `(-> Int Int)` |  | How many distinct strings have been interned. Ids are exactly 0..internCount-1, with no gaps - that is what "dense" means here, and it is what lets a caller size a side table by `internCount` and index it by id. |
| `internLookup` | value | `(-> Int Int String)` | `Alloc,Mut,Unsafe` | The string with id `id`, or an empty `Str` if `id` was never handed out. |
| `internFind` | value | `(-> Int String (Option Int))` |  | The id of a string equal in content to `s`, or `None`. |
| `internIntern` | value | `(-> Int String Int)` | `Alloc,Mut,Unsafe` | The id for `s`, interning it if its content is new. |

## `Json`

`stdlib/Json.ax` — 21 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `jsonNull` | value | `Int` | `Alloc,Mut` |  |
| `jsonBool` | value | `(-> Int Int)` | `Alloc,Mut` |  |
| `jsonNum` | value | `(-> Int Int)` | `Alloc,Mut` | A number from an integer. The raw text is rendered from the value, so `jsonNumText` is total for constructed values as well as parsed ones. |
| `jsonStr` | value | `(-> String Int)` | `Alloc,Mut` |  |
| `jsonArr` | value | `Int` | `Alloc,Mut` |  |
| `jsonObj` | value | `Int` | `Alloc,Mut` |  |
| `jsonIsNull` | value | `(-> Int Bool)` |  |  |
| `jsonBoolVal` | value | `(-> Int Int)` | `Unsafe` |  |
| `jsonInt` | value | `(-> Int Int)` | `Unsafe` | The integer value of a number, 0 for anything else. 0 is a real number, so a caller that must distinguish absence tests `jsonTag` first - the same contract `Utf8`'s -1 sentinel documents. |
| `jsonNumText` | value | `(-> Int String)` | `Unsafe` |  |
| `jsonStrVal` | value | `(-> Int String)` | `Unsafe` |  |
| `jsonArrLen` | value | `(-> Int Int)` | `Unsafe` |  |
| `jsonArrGet` | value | `(-> Int Int Int)` | `Unsafe` |  |
| `jsonArrPush` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` |  |
| `jsonObjLen` | value | `(-> Int Int)` | `Unsafe` |  |
| `jsonObjPut` | value | `(-> Int String Int Int)` | `Alloc,Mut,Unsafe` | The ONLY writer of the two parallel vecs, so they cannot desync. A repeated key appends rather than replacing, which is what a JSON reader that preserves what it was sent should do; `jsonGet` answers the first, matching the usual last-writer-loses reading being avoided here deliberately - LSP never sends duplicates, and inventing a replacement policy would be inventing behaviour no test can pin. |
| `jsonGet` | value | `(-> Int String Int)` |  | The value for `key`, or 0 when there is none. 0 is not a valid value pointer, so it is an unambiguous absence marker AT THIS LAYER - but `jsonTag` reports 0 as `JNULL`, so `jsonIsNull` cannot tell an absent member from one explicitly set to null. A caller that must distinguish the two tests against 0 directly, which is what `lsp.ax`'s dispatch does to tell a request from a notification: an absent `id` means notification, and a null `id` is a different thing the protocol does not let you answer the same way. |
| `jsonGetInt` | value | `(-> Int String Int)` |  |  |
| `jsonGetStr` | value | `(-> Int String String)` |  |  |
| `jsonWrite` | value | `(-> Int String)` | `Alloc,Mut` |  |
| `jsonParse` | value | `(-> String Int)` | `Alloc,Mut` | Parse a whole document: one value, then nothing but whitespace. Answers 0 on any error, which is why every accessor tolerates 0. |

## `Map`

`stdlib/Map.ax` — 26 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `mapHashPrime` | value | `Int` |  | 2^31 - 1, a Mersenne prime. No longer used by `mapHash` itself; kept because `Intern`'s polynomial string hash reduces modulo it, and a prime modulus is what makes that polynomial hash sound. |
| `mapHash` | value | `(-> Int Int)` |  | Hash `key` to a value in [0, 2^63). |
| `mapSlotOf` | value | `(-> Int Int Int)` |  | The slot `key` probes first, in [0, cap). |
| `mapNew` | value | `Map` | `Alloc,Mut` | An empty `Map` with `mapDefaultCap` slots. |
| `mapNewRefVals` | value | `Map` | `Alloc,Mut` | An empty `Map` whose VALUES it owns a share of: the value array carries the array form, so `mapFree` releases every value in it. Keys stay `Int`s and stay a leaf, which is what they are - `mapInsert`'s key parameter is `Int`, not a type variable. |
| `mapWithCapacity` | value | `(-> Int Map)` | `Alloc,Mut` | An empty `Map` sized so that `want` entries fit without rehashing. |
| `mapWithCapacityRefVals` | value | `(-> Int Map)` | `Alloc,Mut` | `mapWithCapacity`'s owning twin. See `mapNewRefVals`. |
| `mapRoundUpPow2` | value | `(-> Int Int)` |  | `n` rounded up to a power of two, at least `mapDefaultCap`. |
| `mapFree` | value | `(-> Map Int)` | `Unsafe` | Hand `m` back: the three arrays go with it, and on a `mapNewRefVals` table so does one share of every value still in it. Answers 0, as `Vec.vecFree` does and for the same reason. The caller must own the released share; aliases cannot be used after the last share is released. |
| `mapLen` | value | `(-> Map Int)` |  |  |
| `mapCap` | value | `(-> Map Int)` |  |  |
| `mapUsed` | value | `(-> Map Int)` |  | Slots that are live or tombstoned. Exposed because it is the number that explains a rehash, and a test that could not see it would have to infer growth from timing. |
| `mapOwnsVals` | value | `(-> Map Bool)` |  | Whether this table owns a share of every value it holds - the `mapNewRefVals` half. Word 6 of the header, and not a test of the value array's shape word: see `mapAllocTable`. |
| `mapKeyAt` | value | `(-> Map Int Int)` | `Unsafe` | Read the key, or the value, out of slot `i`. |
| `mapValAt` | value | `(-> Map Int Int)` | `Unsafe` | The value in slot `i`. See `mapKeyAt` above for the bounds rule and why `mapStateAt` is not exported beside these two. |
| `mapNextSlot` | value | `(-> Int Int Int)` |  | The next slot after `i`. |
| `mapHas` | value | `(-> Map Int Bool)` |  |  |
| `mapGet` | value | `(-> Map Int Int Int)` |  | The value for `key`, or `dflt` if `key` is absent. |
| `mapGetStr` | value | `(-> Map Int String String)` | `Unsafe` | The value for `key` read as a `String`, or `dflt` if `key` is absent. |
| `mapInsert` | value | `(-> Map Int a Int)` | `Alloc,Mut,Unsafe` | Insert or overwrite, growing first if the load factor demands it. |
| `mapRemove` | value | `(-> Map Int Int)` | `Mut,Unsafe` | Delete `key`. Answers 0; see `mapInsert` for why no mutator here answers the handle. |
| `mapLiveFrom` | value | `(-> Map Int (Option Int))` | `Alloc` | The first live slot at or after `i`, or `None` when the table has no live slot from there on. `(mapLiveFrom m 0)` starts an iteration; `(mapLiveFrom m (+ prev 1))` continues one. |
| `mapKeys` | value | `(-> Map (Vec Int))` | `Alloc,Mut` | Every live key, and every live value, in one shared slot order: the `j`th key and the `j`th value came out of the same slot, so the two vectors zip. Both are freshly allocated and the caller owns them. |
| `mapValues` | value | `(-> Map (Vec Int))` | `Alloc,Mut` | Every live value, in the same slot order `mapKeys` uses, so the two vectors zip element for element. |
| `mapSumVals` | value | `(-> Map Int)` |  | The sum of every live value. |
| `mapSumKeys` | value | `(-> Map Int)` |  | The sum of every live key. Together with `mapSumVals` and `mapLen` this pins down a small map's contents well enough to test with. |

## `Mem`

`stdlib/Mem.ax` — 13 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `memAlloc` | value | `(-> Int Int)` | `Alloc,Unsafe` | Allocate `bytes` bytes of zeroed memory and return its address. |
| `memAllocMapped` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` | The same allocation, declaring which of the block's words hold REFERENCES: bit i of `map` says payload word i is a handle to another counted block, so releasing this block releases that one too (docs/memory-model.md MM-LIFE-2d, the record form). |
| `memMarkArray` | value | `(-> Int Int Int)` | `Mut,Unsafe` | The ARRAY FORM: payload words 0..n-1 of this block are handles to other counted blocks, so releasing it releases all of them, and `n` is the caller's ELEMENT count (docs/memory-model.md MM-LIFE-2d names the two forms; the array form landed 2026-08-24 and took its own length 2026-09-03). |
| `memMarkLeaf` | value | `(-> Int Int)` | `Mut,Unsafe` | The inverse, and it is not symmetry for its own sake: it is what a container's GROWTH needs. Doubling a buffer copies the elements to a new block WITHOUT retaining them - the shares move - so releasing the old block while it still reads as an array would spend every share twice. Clearing the bit first makes the old block a leaf, and its release then reclaims the block and touches nothing it used to hold. |
| `memCopy` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | THERE IS NO `memIsArray`, AND THE REASON IS A MEASURED CRASH. |
| `memSet` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` | Set `count` bytes at `addr` to `value` (low 8 bits). Returns `addr`. |
| `memCmp` | value | `(-> Int Int Int Int)` | `Unsafe` | Compare `count` bytes. 0 if equal, otherwise the signed difference of the first differing byte pair (so the result orders like `memcmp`). |
| `memGetWord` | value | `(-> Int Int Int)` | `Unsafe` | The word at `index`. A word is what it is: an integer, or a handle, or a reference whose type this layer does not know. It answers `Int` because that is the truth about a machine word - it used to answer a type variable, which let the CALLER name any type at all and get it, including a reference, which then dereferenced. See `AX3040`. |
| `memGetWordStr` | value | `(-> Int Int String)` | `Unsafe` | The String view, for the typed accessors built on this layer - `tokenLexeme`, `diagCode`, and the several dozen others whose own signature says `String` and whose body is one word read. |
| `memGetWordVec` | value | `(-> Int Int (Vec a))` | `Unsafe` | The `Vec` view of the word at `index`. A `Vec` is a handle - one word, exactly what `memGetWord` answers - so this reinterprets and converts nothing. The cast is HERE, at a return inside a signature that carries the type, for the reason `memGetWordStr` gives: a cast at an argument root classifies that value's evidence 0 and drops its retain or its release (docs/memory-model.md MM-VAL-22, measured). |
| `memSetWord` | value | `(-> Int Int a Int)` | `Mut,Unsafe` | Storing a word here is the moment a value can leave the type system's sight: `(cast Int value)` erases whatever `value` was, and the machine word that lands in `addr` is indistinguishable from an integer forever after. That is the whole of MM-LIFE-2c's co-ownership blocker, and the fix is one line - the store takes a SHARE of what it is about to hide. |
| `memGetByte` | value | `(-> Int Int Int)` | `Unsafe` |  |
| `memPutByte` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  |

## `Net`

`stdlib/Net.ax` — 32 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `SocketAddr` | struct |  |  | An IPv4 or IPv6 address and a port: the kernel's own `sockaddr` bytes for it, `netAddrMaxBytes` long, built by `Sys.netAddr4` and `Sys.netAddr6`. Make one with `socketAddrParse`, `socketAddrV4` or `socketAddrV6`. |
| `socketAddrV4` | value | `(-> Int Int Int Int Int (Result SocketAddr Error))` | `Alloc,Mut,Unsafe` | The address `a.b.c.d:port`. Each part must be in range: 0..255 for the octets and 0..65535 for the port. |
| `socketAddrV6` | value | `(-> (Vec Int) Int (Result SocketAddr Error))` | `Alloc,Mut,Unsafe` | The address `[g0:g1:...:g7]:port` from eight 16-bit groups, each in 0..65535. `groups` must hold exactly eight. |
| `socketAddrParse` | value | `(-> String (Result SocketAddr Error))` | `Alloc,Mut` | Read a socket address from text: `a.b.c.d:port` for IPv4, or `[ipv6]:port` with the brackets RFC 3986 section 3.2.2 requires, so the port can't be mistaken for a group. Only numeric addresses: see the header for why there are no names. |
| `socketAddrText` | value | `(-> SocketAddr String)` | `Alloc,Mut,Unsafe` | The address as text, `a.b.c.d:port` or `[ipv6]:port`, with IPv6 in the RFC 5952 form: lower-case, the longest run of zero groups as `::`, and an IPv4-mapped address as `::ffff:a.b.c.d`. |
| `socketAddrIp` | value | `(-> SocketAddr String)` | `Alloc,Mut,Unsafe` | The IP address alone, with no port and no brackets. |
| `socketAddrPort` | value | `(-> SocketAddr Int)` | `Unsafe` | The port, or -1 for an address this module did not build. |
| `socketAddrIsV6` | value | `(-> SocketAddr Bool)` | `Unsafe` | Whether the address is IPv6. |
| `TcpListener` | struct |  |  | A socket listening for connections. |
| `TcpStream` | struct |  |  | One TCP connection. |
| `tcpListenerFd` | value | `(-> TcpListener Int)` |  | The listener's descriptor, for `Sys`'s readiness calls. It stays the listener's: close the listener, not the descriptor. |
| `tcpStreamFd` | value | `(-> TcpStream Int)` |  | The stream's descriptor, for `Sys`'s readiness calls. |
| `tcpListen` | value | `(-> SocketAddr (Result TcpListener Error))` | `Alloc,IO,Mut,Unsafe` | A socket bound to `addr` and listening, with `SO_REUSEADDR` set so a restarted server can bind the port its predecessor left in TIME_WAIT. Port 0 asks the kernel for a free port; `tcpListenerAddr` says which. |
| `tcpAccept` | value | `(-> TcpListener (Result TcpStream Error))` | `Alloc,IO,Mut` | Wait for the next connection and answer it as a blocking stream. |
| `tcpListenerAddr` | value | `(-> TcpListener (Result SocketAddr Error))` | `Alloc,IO,Mut` | The address the listener is bound to - the kernel's choice of port when it was asked for port 0. |
| `tcpListenerClose` | value | `(-> TcpListener (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Close the listener. Its handle is retired first, so any later use of it stops the program with status 85. |
| `tcpConnect` | value | `(-> SocketAddr (Result TcpStream Error))` | `Alloc,IO,Mut,Unsafe` | Connect to `addr`, waiting until the connection is made or refused. |
| `tcpRead` | value | `(-> TcpStream String Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Read into `buf[at .. at + count)`. Answers how many bytes arrived, and 0 when the peer has closed its side. A range outside `buf` stops the program with status 77 before the kernel sees it, as `IO.readInto` does. |
| `tcpReadSome` | value | `(-> TcpStream Int (Result String Error))` | `Alloc,IO,Mut,Unsafe` | Up to `max` bytes, as a fresh string: empty when the peer has closed its side. |
| `tcpReadAll` | value | `(-> TcpStream (Result String Error))` | `Alloc,IO,Mut` | Everything until the peer closes its side. |
| `tcpWrite` | value | `(-> TcpStream String (Result Int Error))` | `Alloc,IO,Unsafe` | Write all of `data`, continuing after a short write. Answers the number of bytes written, which is `strLen data` unless it failed. A peer that has closed answers `Err` EPIPE rather than a signal. |
| `shutRead` | value | `Int` |  | Which half of a connection `tcpShutdown` closes. |
| `shutWrite` | value | `Int` |  |  |
| `shutBoth` | value | `Int` |  |  |
| `tcpShutdown` | value | `(-> TcpStream Int (Result Int Error))` | `Alloc,IO` | Close one or both halves of the connection without closing the stream: after `shutWrite` the peer reads end of stream, and this side can still read its answer. |
| `tcpPeerAddr` | value | `(-> TcpStream (Result SocketAddr Error))` | `Alloc,IO,Mut` | The peer's address. |
| `tcpLocalAddr` | value | `(-> TcpStream (Result SocketAddr Error))` | `Alloc,IO,Mut` | This side's address. |
| `tcpSetNoDelay` | value | `(-> TcpStream Bool (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Turn Nagle's algorithm off (`true`) or back on: with it off, a small write is sent at once rather than held to be joined with the next. |
| `tcpSetReadTimeout` | value | `(-> TcpStream Int (Result Int Error))` | `Alloc,IO,Mut` | How long a read may wait before it answers `Err` (EAGAIN), in microseconds; 0 waits for ever. |
| `tcpSetWriteTimeout` | value | `(-> TcpStream Int (Result Int Error))` | `Alloc,IO,Mut` | How long a write may wait before it answers `Err`, in microseconds; 0 waits for ever. |
| `tcpSetNonBlocking` | value | `(-> TcpStream Bool (Result Int Error))` | `Alloc,IO` | Switch the stream between blocking (`false`) and non-blocking (`true`). |
| `tcpClose` | value | `(-> TcpStream (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Close the stream. Its handle is retired first, so any later use of it stops the program with status 85. |

## `Par`

`stdlib/Par.ax` — 5 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `parMapWords` | value | `(-> (-> Int Int) Int Int (Vec Int))` | `Alloc,Block,IO,Mut,Spawn,Unsafe` | Run `f i` for every `i` in `0 .. n`, at most `width` at once, answering the results in SUBMIT order. |
| `parMapWordsChecked` | value | `(-> (-> Int Int) Int Int (Vec (Result Int Error)))` | `Alloc,Block,IO,Mut,Spawn,Unsafe` | Run `f i` for every `i` in `0 .. n`, at most `width` at once, answering one `Result` per slot in SUBMIT order: `Ok` the thunk's word, `Err` the wait status of a slot whose thunk trapped. |
| `parArgvVector` | value | `(-> (Vec String) Int)` | `Alloc,Mut,Unsafe` | A NULL-terminated array of char* from a Vec of `String`, which is the shape `execve` and `posix_spawn` both take. |
| `parRunOne` | value | `(-> (Vec String) (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Run one argv - element 0 is the program, looked up on `PATH` the way `sysRunPath` does it. |
| `parRunAll` | value | `(-> (Vec (Vec String)) Int (Vec Int))` | `Alloc,Block,IO,Mut,Spawn` | Run every command in `cmds` at up to `width` at once, answering their exit codes in the order they appear in `cmds`. |

## `Path`

`stdlib/Path.ax` — 11 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `pathLastSlash` | value | `(-> String (Option Int))` |  | The last `/` in `p`, or `None`. Everything below is a decision about this one index. `compat/SENTINELS`'s direction rule is "absence wants `Option`", and this is the primitive every caller in this file goes through - `pathExtIndex` is the one exception, and it goes straight to the raw `-1` helper below because it needs the sentinel back in arithmetic (`(+ slash 1)` is 0, correctly, when there is no slash at all), not a value to branch on. |
| `pathDir` | value | `(-> String String)` | `Alloc,Mut` | Everything up to and INCLUDING the last `/`, or "" when `p` names something in the working directory. |
| `pathBase` | value | `(-> String String)` | `Alloc,Mut` | Everything after the last `/` - the file name on its own, or `p` entire when there is no separator. |
| `pathWithSlash` | value | `(-> String String)` | `Alloc,Mut` | A directory name that ends in `/`, so concatenation forms a path. |
| `pathJoin` | value | `(-> String String String)` | `Alloc,Mut` | `dir` and `name` as one path, with exactly one `/` between them. |
| `pathExtIndex` | value | `(-> String (Option Int))` |  | The index of the extension's `.` within `p`, or `None`. |
| `pathExt` | value | `(-> String String)` | `Alloc,Mut` | The extension INCLUDING its dot (`".ax"`), or "" when there is none. |
| `pathStem` | value | `(-> String String)` | `Alloc,Mut` | The base name with its extension removed: `"src/main.ax"` is `"main"`. What a driver names an output after. |
| `pathReplaceExt` | value | `(-> String String String)` | `Alloc,Mut` | `p` with its extension replaced by `ext`, which carries its own dot. `(pathReplaceExt "build/main.ax" ".ll")` is `"build/main.ll"`, and a path with no extension simply gains one. |
| `pathIsAbsolute` | value | `(-> String Bool)` |  | True when `p` starts at the root. A relative path is resolved against the working directory, which is why `Sys.sysGetCwd` exists. |
| `pathClean` | value | `(-> String String)` | `Alloc,Mut` | `p`, lexically simplified to the shortest path naming the same location: doubled `/`s collapse, a `.` segment is dropped, and a real segment is cancelled by the `..` that immediately follows it. Nothing here touches the filesystem - a symlink component is resolved exactly as if it were an ordinary name, which is what makes this a STRING operation and not a `Sys` one. Same rules as Go's `path.Clean` or Python's `posixpath.normpath`. |

## `Pre`

`stdlib/Pre.ax` — 7 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `when` | macro |  |  | Axiom standard prelude — macros and utilities. |
| `unless` | macro |  |  | ;; unless — evaluate body unless test is true ;; (unless test body) -> (if test 0 body) |
| `range` | macro |  |  | ;; range — the counted loop: `(range i 0 n body)` is `0..n` ;; (range i lo hi body) -> `body` once per `i` in [lo, hi), ascending, ;; with both ends read ONCE. |
| `deriveEq` | macro |  |  | ;; Variadic branching is the `if` statement itself: `(if t1 b1 t2 b2 ;; ... els)` is the nested chain `(if t1 b1 (if t2 b2 ... els))`, ;; built by the parser. The fixed-arity `cond2`/`cond3` helpers that ;; used to stand here are gone with the `cond` keyword (AX2004): ;; spell the nesting with `if`. ;; deriveEq — structural equality for a data type, derived at the ;; point of use: `(deriveEq Color)` generates `eqColor : Color -> ;; Color -> Bool`, one match arm per constructor, answered from the ;; declaration list at expansion time (macro-system.md MAC-CAP-5/9). ;; The nullary form: works for any sum of nullary constructors, which ;; is the enum case. Fieldful sums want the impl form written where ;; the Eq trait is in scope — see macro-system.md section 10.2. |
| `deriveShow` | macro |  |  | ;; deriveShow — the constructor's own name, as a String, for any ;; `data` type: `(deriveShow Shape)` generates `showShape : Shape -> ;; String`. This is what `syntax/name` exists for (macro-system.md ;; MAC-CAP-5), and the only way to get a constructor's spelling into ;; a running program: a tag is an integer at run time and the name ;; lives only in the declaration list the expander reads. ;; ;; Fieldful constructors are matched and their fields ignored - ;; `(syntax/binders C f)` supplies exactly arity-of-C binders, so one ;; template covers arities 0, 1 and n without an arity test. Rendering ;; the FIELDS would need each field's type to pick a printer, and a ;; macro cannot see a type (MAC-CAP-7); a program that wants that ;; writes the arm itself. |
| `deriveArity` | macro |  |  | ;; deriveArity — how many fields the value's constructor carries: ;; `(deriveArity Shape)` generates `arityShape : Shape -> Int`. The ;; count is `syntax/arity`'s answer, folded to a literal per arm, and ;; it is not derivable any other way at run time: a heap block records ;; its tag, never its field count (memory-model.md MM-VAL-6). |
| `showOr` | macro |  |  | ;; showOr — `(showOr T x fallback)` renders `x` with the type's ;; derived `showT` when the program has one, and answers `fallback` ;; when it does not. `syntax/defined` decides that at expansion time ;; and the losing branch is DELETED rather than compiled, which is ;; the whole point: the branch that names `showT` is only well-typed ;; in a program that derived it, so a runtime `if` over both arms ;; would be AX3001 in every program that did not. |

## `Rpc`

`stdlib/Rpc.ax` — 8 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `rdNew` | value | `(-> Int Int)` | `Alloc,Mut,Unsafe` |  |
| `rdBuf` | value | `(-> Int String)` | `Unsafe` |  |
| `rdFilled` | value | `(-> Int Int)` | `Unsafe` |  |
| `rdConsumed` | value | `(-> Int Int)` | `Unsafe` |  |
| `rdReseat` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` | Re-seat a reader on freshly allocated storage, carrying `u` bytes of not-yet-consumed input from `addr`. |
| `rpcReadMsg` | value | `(-> Int (Option String))` | `Alloc,IO,Mut,Unsafe` | Read one whole message: `Some` its body, or `None` when the stream ended or broke - the caller stops, which is what an LSP does when its client goes away without saying `exit`. |
| `rpcRead` | value | `(-> Int String)` | `Alloc,IO,Mut` | Read one whole message and answer its body, or "" when the stream ended or broke. A zero-length message answers "" too, so a caller that must tell the two apart reads with `rpcReadMsg`. |
| `rpcWrite` | value | `(-> Int String Int)` | `Alloc,IO,Mut` | Frame `body` and write it. |

## `Str`

`stdlib/Str.ax` — 31 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `strWrap` | value | `(-> Int Int String)` | `Alloc,Mut,Unsafe` | Wrap `len` bytes at `bytes` as a `Str` without copying. |
| `strWrapOwned` | value | `(-> Int Int Int String)` | `Alloc,Mut,Unsafe` | The same, naming the block that OWNS the bytes (MM-LIFE-2d's `Str` half): word 2 holds the handle whose death should free them, or 0 when no such block exists - a literal's bytes are loader-resident, a syscall's are the kernel's, and an interior wrap over an arena keep block belongs to the arena. A slice inherits its parent's owner rather than naming the parent, so the chain is one hop deep however many times a slice is sliced, and the address counted is never interior. |
| `strAlloc` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | A `Str` over freshly allocated, zeroed space for `len` bytes. |
| `strFromLit` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | A `Str` sharing the bytes at a NUL-terminated address. |
| `cstrLen` | value | `(-> Int Int Int)` | `Unsafe` | Length of NUL-terminated bytes at `addr`, scanning from `i`. |
| `strLen` | value | `(-> String Int)` | `Unsafe` |  |
| `strData` | value | `(-> String Int)` | `Unsafe` |  |
| `strOwner` | value | `(-> String Int)` | `Unsafe` | The block owning this string's bytes, or 0 for bytes no block owns (a literal's, a syscall buffer's, an arena keep block's interior). |
| `strByte` | value | `(-> String Int Int)` | `Unsafe` | The byte at `i`, or 0 when `i` is out of range. |
| `strCStr` | value | `(-> String Int)` |  | The bytes of `s` as a NUL-terminated address, for handing to a syscall. |
| `strIsEmpty` | value | `(-> String Bool)` |  |  |
| `strCmp` | value | `(-> String String Int)` | `Unsafe` | 0 when equal; otherwise negative if `a` sorts before `b`, positive if after - lexicographic by unsigned byte, with a shorter prefix sorting first. |
| `strEq` | value | `(-> String String Bool)` | `Unsafe` | Equality, which is NOT `strCmp a b == 0` even though it answers the same thing. `strCmp` must produce an ORDERING, so it memcmps the shared prefix before it ever looks at the lengths - and equality does not need the ordering. Two strings of different lengths are unequal whatever their bytes say, so checking the length first turns the commonest case, a miss, into two word loads and a compare. |
| `strSlice` | value | `(-> String Int Int String)` | `Alloc,Mut,Unsafe` | The `count` bytes of `s` starting at `start`, sharing `s`'s storage. |
| `strDup` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | An owned, NUL-terminated copy of `s`. |
| `strConcat` | value | `(-> String String String)` | `Alloc,Mut,Unsafe` |  |
| `strFindByte` | value | `(-> String Int Int (Option Int))` |  | Index of the first `byte` at or after `from`, or `None`. |
| `strStartsWith` | value | `(-> String String Bool)` | `Unsafe` |  |
| `strIsDigit` | value | `(-> Int Bool)` |  |  |
| `strIsAlpha` | value | `(-> Int Bool)` |  |  |
| `strIsSpace` | value | `(-> Int Bool)` |  | Space, tab, LF, CR - and nothing else. Not `char::is_whitespace`: VT and FF are AX1001 to this language's lexer, and a formatter that skipped them turned a refused file into an accepted one. |
| `strHexVal` | value | `(-> Int (Option Int))` |  | The value of a hex digit, or `None`. Stated as the VALUE and not as a predicate because the value is what every caller needed: the JSON parser's `\uXXXX` escape and the language server's percent-decoding each carried a byte-identical copy of this ladder under its own name, while the predicate here had no caller at all. |
| `strIsHexDigit` | value | `(-> Int Bool)` |  |  |
| `strSplit` | value | `(-> String Int (Vec String))` | `Alloc,Mut` | Every segment of `s` between occurrences of `byte`, in order, as a `(Vec String)`. Empty segments are KEPT: a `PATH` entry of "" means the working directory, and a caller that wants them dropped can drop them, while a caller that needs them cannot get them back. `strSplit "" 58` answers one empty segment, and `strSplit "a:" 58` answers two - the same rule as splitting on a separator anywhere else, and the one that makes the segment count equal the separator count plus one. |
| `strSplitFrom` | value | `(-> String Int Int (Vec String) Int)` | `Alloc,Mut` |  |
| `strFromByte` | value | `(-> Byte String)` | `Alloc,Mut,Unsafe` | A one-byte `Str` holding `b`. The compiler driver and the JSON encoder each had this three-line allocate-and-store under a private name; it is a `Str` constructor, so it lives with the others. |
| `strLower` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | `s` with every ASCII upper-case byte lowered, or `s` itself when it has none - so a header name already in the form a table wants is not copied. Bytes above 127 pass through untouched: this is the ASCII fold a case-insensitive header table needs, not a Unicode case mapping. |
| `strFind` | value | `(-> String String Int (Option Int))` | `Unsafe` | The index of the first occurrence of `needle` in `s` at or after `from`, or `None`. An empty needle is found at `from` whenever `from` is inside `s` or at its end, which is the rule that makes `(strFind s "" (strLen s))` answer `(Some (strLen s))` rather than nothing. `no-alloc` came off on 2026-08-31: the `(Some found)` answer allocates. Accepted until then because a constructor contributed nothing to the effect row (`MM-EXEC-9a`). `no-io` and `no-foreign` are unchanged. |
| `strTrim` | value | `(-> String String)` | `Alloc,Mut` | `s` without the `strIsSpace` bytes at either end, as a SLICE that shares `s`'s storage - so it is not NUL-terminated unless it ends where `s` does, exactly as `strSlice` says. A string that is all space trims to "". |
| `strParseInt` | value | `(-> String (Option Int))` |  | The decimal integer `s` spells - an optional `-`, then one or more ASCII digits and nothing else - or `None`: for an empty string, a sign alone, any other byte, and any value outside the 64-bit range. |
| `format` | macro |  |  | `format` — a String, built at compile time from a literal's runs and holes, or the hole lowering applied to anything else. |

## `Sys`

`stdlib/Sys.ax` — 105 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `sysResult` | value | `(-> String Int (Result Int Error))` | `Alloc` | The errno behind a failed result, or 0 if it did not fail. |
| `stdin` | value | `Int` |  |  |
| `stdout` | value | `Int` |  |  |
| `stderr` | value | `Int` |  |  |
| `sysWriteFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | write(2): `Ok` bytes written - possibly fewer than asked, which is what `sysWriteAllFd` below exists to retry - or `Err` carrying the errno. `(Result Int Error)` since 2026-09-03; the sentinel it replaced is recorded in `sysWriteAllFd`'s header, with why it stood and what let it go. |
| `sysWriteAllFd` | value | `(-> Int Int Int Int Int)` | `Alloc,IO,Unsafe` | THREE OUTCOMES, AND THE Int CHANNEL HELD TWO. Until 2026-08-30 this answered `done` when `write` returned exactly 0 - a short, NON-NEGATIVE count, indistinguishable from the complete one. The comment above calls treating a short write as success "the classic way to truncate output", and that is what this did in the one case it cannot retry. |
| `sysReadFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | read(2): `Ok` bytes read, `Ok 0` at end of input, or `Err` carrying the errno. `(Result Int Error)` since 2026-09-03, on the same terms as `sysWriteFd`: every reader in the tree matches the call directly and pays for no block on the bytes-arrived path. |
| `sysOpenPath` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | ANSWERS `(Result Int Error)` - the descriptor, or the errno `open` refused with. This is the port `docs/error-model.md` ERR-ADOPT-1 calls the canonical one: a failed open is what a reader checks first when deciding whether the error model is real, and ENOENT, EACCES and EISDIR are three different things a caller does three different things about. As an `Int` they were all "negative". |
| `sysCloseFd` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Close a descriptor. |
| `sysExitWith` | value | `(-> Int Int)` | `IO,Unsafe` |  |
| `sysFailed` | value | `(-> Int Bool)` |  |  |
| `sysErrno` | value | `(-> Int Int)` |  |  |
| `sysReadFile` | value | `(-> Int String)` | `Alloc,IO,Mut,Unsafe` | Open, read entire contents, close.  Returns an empty string on any error (missing file, permission, etc.). |
| `sysArgc` | value | `Int` | `IO` | How many arguments the process received, including the program name. |
| `sysArg` | value | `(-> Int String)` | `Alloc,IO,Mut,Unsafe` | The i-th argument as a Str (0 is the program name), or "" when `i` is out of range. The bytes are the process's own argv storage - NUL-terminated, alive for the whole run, never freed or moved - so wrapping them without copying is sound. |
| `sysWriteFile` | value | `(-> Int String (Result Int Error))` | `Alloc,IO,Unsafe` | Write `s` to `path`, creating or truncating it. Answers the number of bytes written, or a negative errno from whichever step failed. |
| `sysAppendFile` | value | `(-> Int String (Result Int Error))` | `Alloc,IO,Unsafe` | Append `s` to `path`, creating it if it is not there. Answers the number of bytes written, or a negative errno. |
| `sysRename` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Rename `old` to `new`, answering 0 or `-errno`. Both are NUL-terminated char* - `strCStr`. |
| `sysUnlink` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Remove `path`. Answers 0, or `-errno`. |
| `sysMkdir` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Create directory `path` with `mode`. Answers 0, or `-errno` - which is `-17` (EEXIST) when it is already there, and callers usually want to treat that as success. |
| `sysDirMode` | value | `Int` |  | 0755, the mode a directory usually wants. A nullary function because that is how this language spells a constant. |
| `sysRmdir` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Remove the empty directory `path`. Answers 0, or `-errno`. |
| `sysSymlink` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Create the symbolic link `link` whose content is `target`, both NUL-terminated addresses. Answers `Ok 0`, or the errno. |
| `sysOpenBeneath` | value | `(-> Int String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Open `rel` for reading inside the directory `root` (a NUL-terminated address), following no symlink below it: the descriptor, or the errno. |
| `sysFileExists` | value | `(-> Int Bool)` | `Alloc,IO,Unsafe` | 1 when `path` names something that can be opened for reading. |
| `sysFileSize` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | The size of `path` in bytes, or `-errno`. Seeks to the end, which is what the size IS - no struct, no layout, no per-target record. |
| `sysReadErrno` | value | `(-> Int Int)` | `Alloc,IO,Mut,Unsafe` | 0 when `path` can be opened AND read as a file, otherwise the errno saying why not. |
| `sysIsDir` | value | `(-> Int Bool)` | `Alloc,IO,Mut,Unsafe` | True when `path` names a directory. |
| `sysReadDir` | value | `(-> Int (Vec String))` | `Alloc,IO,Mut,Unsafe` | Every name in the directory `path`, as a Vec of owned `Str` - `.` and `..` INCLUDED, in whatever order the filesystem gives them. |
| `sysGetCwd` | value | `(Result String Error)` | `Alloc,IO,Mut,Unsafe` | The process's working directory as an absolute path: `(Ok path)`, or `(Err e)` whose code is the errno the kernel refused with. |
| `sysEnv` | value | `(-> String String)` | `Alloc,IO,Mut` | The value of the environment variable `name`, or "" when it is unset. |
| `sysEnvp` | value | `Int` | `Alloc,IO,Mut,Unsafe` | A NULL-terminated copy of the process's own environment vector, in the form a child expects. |
| `sysSpawn` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Start `path` with argument vector `argv` and environment `envp`. `(Ok pid)`, or `(Err e)` whose code is the errno - and `Err` means no child exists, which is what a caller must not confuse with a child that started and failed. |
| `sysWaitPid` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Wait for `pid`. `(Ok status)` is the raw wait status; `(Err e)` carries the errno of a wait that could not be performed. |
| `sysExitCode` | value | `(-> Int Int)` |  | The exit code carried by a wait status, for a child that exited normally. |
| `sysTermSignal` | value | `(-> Int Int)` |  | The signal that killed a child, or 0 if it exited normally. |
| `sysRun` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Run `path` to completion and answer its exit code. |
| `sysRunPath` | value | `(-> String Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Run `name`, searching `PATH` for it when it contains no slash. |
| `sysGetPid` | value | `Int` | `IO,Unsafe` | The calling process's own id - the per-session suffix scratch files need so two concurrent processes cannot collide. The syscall takes no arguments; the unused ones are simply zero. |
| `sysNowMicros` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Microseconds now, from the platform's cheapest correct clock: Darwin answers gettimeofday's timeval (realtime; Darwin's syscall table has no clock_gettime), Linux and FreeBSD answer CLOCK_MONOTONIC via clock_gettime - under the id `clockMonotonicId` names, because the id is not portable: 1 on Linux, and on FreeBSD 4, where 1 is CLOCK_VIRTUAL, the process's CPU time. That one was a literal here until 2026-08-29, and a clock that measures CPU time never runs backwards either, so nothing would have caught it. |
| `sysNowMonotonic` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Microseconds from a clock that NEVER steps backwards, or `Err` when this platform has none. The 16-byte buffer is the caller's, as above, so a timing loop allocates nothing on the path that answers. |
| `netSocketTcp` | value | `(Result Int Error)` | `Alloc,IO,Unsafe` | A TCP socket, as `(Result Int Error)`. |
| `netSocketTcp6` | value | `(Result Int Error)` | `Alloc,IO,Unsafe` | The same over IPv6. Its own name rather than a family parameter, because the family is not a runtime choice at this layer: a caller already picked a builder when it made the address, and a socket whose family disagrees with the address it is given fails at `bind` and not here. |
| `netAddr4Bytes` | value | `Int` |  | How many bytes an address of each family occupies, and how big a buffer that must take either has to be. |
| `netAddr6Bytes` | value | `Int` |  |  |
| `netAddrMaxBytes` | value | `Int` |  | What `netAcceptFrom` wants, which is the larger of the two: a caller does not get to know the peer's family until it has the peer. |
| `netAddr4` | value | `(-> Int Int Int Int Int Int Int)` | `Mut,Unsafe` | Write an IPv4 `sockaddr_in` into `buf`, which must hold 16 bytes, and answer `buf`. The four octets are given in reading order, so 127.0.0.1 is `127 0 0 1`. |
| `netAddr6` | value | `(-> Int Int Int Int Int Int Int Int Int Int Int)` | `Mut,Unsafe` | Write an IPv6 `sockaddr_in6` into `buf`, which must hold `netAddr6Bytes`, and answer `buf`. |
| `netAddrFamily` | value | `(-> Int Int)` | `Unsafe` | The address family in a `sockaddr` - `afInet`, `afInet6`, or whatever else the kernel wrote there. |
| `netAddrPort` | value | `(-> Int Int)` | `Unsafe` | The port in a `sockaddr`, decoded from network order. This one does NOT branch on the platform or the family: both layouts diverge in the four bytes before it and agree from byte 2 on, so `sin_port` and `sin6_port` are the same two bytes in the same place. |
| `netAddrSize` | value | `(-> Int Int)` | `Unsafe` | How many bytes of `addr` a syscall must be given, read off the family the buffer carries. This is what `netBind` and `netConnect` pass, and the reason neither of them takes a length. |
| `netBind` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Bind a socket to an address built by `netAddr4` or `netAddr6`. |
| `netListen` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Answers `(Result Int Error)`; `Ok 0` on success. |
| `netAccept` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Accept a connection, answering `Ok` the new socket or `Err` the errno - `(Result Int Error)` since 2026-09-03; a would-block answer is `Err` carrying EAGAIN, which `netWouldBlock` still recognises from the negated code - and throw the peer's address away. `netAcceptFrom` below keeps it; this is the form for a caller that does not want the buffer, and it passes NULL for both of `accept`'s out-parameters. |
| `netAcceptFrom` | value | `(-> Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Accept a connection AND KEEP THE PEER'S ADDRESS. Answers the new socket or a negative errno, exactly as `netAccept` does, and fills `addr` with the peer's `sockaddr`, which `netAddrFamily`, `netAddrPort` and `netAddrText` read. |
| `netAddrLenRead` | value | `(-> Int Int)` | `Unsafe` | The length the kernel wrote back into a `netAcceptFrom` cell - 16 for a v4 peer, 28 for a v6 one - as normalised by `netAcceptFrom`. It is the REAL length of the peer's address, which is not necessarily how much of it arrived: Linux and Darwin copy what fits and report the whole size, FreeBSD reports the copied size and `netAcceptFrom` reads the whole one back off the BSD length byte, so a value larger than the `cap` that went in means the address was cut short on every target. `netAcceptFrom` acts on that itself; a caller reads this to log the family it could not store. |
| `netAddrText` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | Render an address as text: a dotted quad for `afInet`, RFC 5952 form for `afInet6`. |
| `netAddrTextPort` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | The same, with the port, in the form a URL authority uses: `127.0.0.1:80` and `[::1]:80`. |
| `netSetBlocking` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Take a descriptor OUT of non-blocking mode, preserving the other flags it carries. The counterpart of `netSetNonBlocking`, and what a caller that handles one connection synchronously wants from `netAccept`'s result. |
| `netConnect` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Connect to an address built by `netAddr4` or `netAddr6`. The length comes off the family in the buffer for the same reason `netBind`'s does, and was the same literal 16. |
| `netShutdown` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Answers `(Result Int Error)`; `Ok 0` on success. |
| `netSetOptBytes` | value | `(-> Int Int Int Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Set a socket option whose value is `len` bytes at `buf` - a struct such as the `timeval` `SO_RCVTIMEO` takes, where `netSetOptInt` covers the four-byte ones. |
| `netGetSockName` | value | `(-> Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | The address socket `fd` is bound to (`getsockname`), written into the `cap` bytes at `addr` with the length cell at `lenbuf`, as `netAcceptFrom` writes a peer. How a listener asked for port 0 learns the port it got. |
| `netGetPeerName` | value | `(-> Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | The address of the peer connected to socket `fd` (`getpeername`), in the same shape. |
| `netSetOptInt` | value | `(-> Int Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Set an integer-valued socket option. The value crosses as four bytes in the host's own order, which is what the kernel reads an `int` option as - unlike an address, this one is NOT network order. That is `netPutInt32`, which `netAcceptFrom`'s `socklen_t` cell needs for the same reason. |
| `netSetNonBlocking` | value | `(-> Int (Result Int Error))` | `Alloc,IO` | Put a descriptor into non-blocking mode, preserving the flags it already carries - a bare `F_SETFL` of the one flag would clear the access mode with it. |
| `netWouldBlock` | value | `(-> Int Bool)` |  | Whether a negative answer means "nothing to take yet" rather than a broken socket. This is the whole reason `eAgain` is a capability: the number is 35 on Darwin and 11 on Linux, so an event loop written against a literal runs correctly on the machine it was written on. |
| `netPollBufBytes` | value | `(-> Int Int)` |  | How many bytes an event buffer for `n` events needs on this platform. |
| `netPollCreate` | value | `(Result Int Error)` | `Alloc,IO,Unsafe` | A readiness descriptor, as `(Result Int Error)`. |
| `netPollAddRead` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Watch `fd` for readability. `rec` is scratch of `pollEventSize` bytes. |
| `netPollDelRead` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Answers `(Result Int Error)`; `Ok 0` on success. |
| `netPollWait` | value | `(-> Int Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Wait for readiness, answering `Ok` how many events landed in `buf` or `Err` the errno - `(Result Int Error)` since 2026-09-03, matched directly by every wake loop so the wake itself builds no block. A NEGATIVE `timeoutMs` BLOCKS INDEFINITELY, which is what a server's accept loop wants; zero polls and returns at once. |
| `netPollFdAt` | value | `(-> Int Int Int)` | `Unsafe` | The descriptor named by event `i` of a buffer `netPollWait` filled. |
| `sysRandomBytes` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Fill `n` bytes at `buf` with kernel entropy. `(Ok 0)`, or `(Err e)` whose code is the errno - and on `Err` the buffer's contents are unspecified, so a caller must not read them. |
| `sysSigBit` | value | `(-> Int Int)` |  | The `sigset_t` bit for a signal. SIGNAL N IS BIT N-1, an off-by-one that is easy to write the other way and yields the neighbouring signal's mask rather than an error. |
| `sysSignalBlock` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Block the signals in `mask` so they become observable instead of fatal. `setbuf` is caller scratch of at least 16 bytes: the mask is written as one 64-bit word, and the kernel then copies ITS OWN `sigset_t` width out of the buffer - `sigsetBytes`, which is 4 on Darwin, 8 on Linux and 16 on FreeBSD. Sixteen covers every target, and the bytes between the word and that width are zeroed here rather than left to whatever the caller's buffer held, because on FreeBSD they are signals 65 through 128 and a stale byte there blocks one. Answers `(Result Int Error)`; `Ok 0` on success. Runs once, before a server forks, so that every worker inherits the mask. |
| `netSignalOpen` | value | `(-> Int Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Watch the signals in `mask` on the readiness descriptor `pfd`, and answer a HANDLE to pass back to `netPollSignalAt` - the signal descriptor on Linux, and 0 on the BSDs, which need none. |
| `netPollSignalAt` | value | `(-> Int Int Int Int (Option Int))` | `IO,Unsafe` | The signal named by event `i`, or `None` when that event is not a signal at all. `sigHandle` is what `netSignalOpen` answered and `scratch` is caller scratch of at least `sigInfoSize` bytes. |
| `sysKill` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Send a signal, which is how a test raises one against itself. |
| `sysForkProcess` | value | `Int` | `IO,Unsafe` | Duplicating this process |
| `sysTermStateBytes` | value | `Int` |  | How many bytes a saved terminal state occupies, which is how large the buffer a caller hands `sysTermSave`, `sysTermRaw` and `sysTermRestore` must be. 72, 36 or 44 depending on the target; 0 where there is no `termios` at all. |
| `sysTermSizeBytes` | value | `Int` |  | The bytes `sysTermSize` writes. 8 on every target that has one; see the section header for why this number is here and not in `Sys.Platform`. |
| `sysIsatty` | value | `(-> Int Bool)` | `Alloc,IO,Unsafe` | True when `fd` is a terminal. |
| `sysTermSave` | value | `(-> Int Int Int)` | `IO,Unsafe` | Read `fd`'s current terminal attributes into `save`, which must hold `sysTermStateBytes` bytes. 0 on success, or a negative result. |
| `sysTermRestore` | value | `(-> Int Int Int)` | `IO,Unsafe` | Write `state` back to `fd` as its terminal attributes: 0, or a negative result. |
| `sysTermRaw` | value | `(-> Int Int Int Int)` | `Alloc,IO,Mut,Unsafe` | Put `fd` into raw mode, having first saved its current state into `save` (`sysTermStateBytes` bytes, owned by the caller). 0, or a negative result. |
| `sysTermSize` | value | `(-> Int Int Int)` | `IO,Unsafe` | Read `fd`'s window size into `buf` (`sysTermSizeBytes` bytes): 0, or a negative result. `sysTermRows` and `sysTermCols` read the answer back out. |
| `sysTermRows` | value | `(-> Int Int)` | `Unsafe` | Rows out of a buffer `sysTermSize` filled. `ws_row` is an `unsigned short` at offset 0 on every target, little-endian. |
| `sysTermCols` | value | `(-> Int Int)` | `Unsafe` | Columns: `ws_col`, the second `unsigned short`. |
| `sysReadAllFd` | value | `(-> Int (Result String Error))` | `Alloc,IO,Mut,Unsafe` | Read `fd` to end of input: `Ok` the whole stream, `Ok ""` when nothing arrived, or `Err` carrying the errno of the `read` that failed. |
| `sysReadLineFd` | value | `(-> Int (Result (Option String) Error))` | `Alloc,IO,Mut,Unsafe` | One line of `fd`: `Ok (Some line)` without its newline, `Ok None` at end of input when nothing was read, or `Err` carrying the errno. |
| `sysMapShared` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Map `len` bytes, readable and writable (PROT_READ\|PROT_WRITE = 3), shared with every binding spawned after this call; answers the address, page-aligned and zeroed. Unmap it with `sysUnmapShared` once no binding can still touch it - a program obligation, as a handle's single join is (MM-PAR-8). |
| `sysUnmapShared` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  |
| `sysMapPrivate` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` | Map `len` zeroed bytes, readable and writable, private to this process: a fork gets a copy, as it does of the arena. Answers the page-aligned address. |
| `sysUnmapPrivate` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  |
| `sysMlock` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Lock `len` bytes at `addr` into memory, so the kernel never writes them to swap. The kernel may refuse: `RLIMIT_MEMLOCK` caps how much an unprivileged process may lock, and on Linux the default cap is a few megabytes. A refusal is an `Err` the caller decides about. |
| `sysMunlock` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  |
| `sysExcludeFromCore` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` | Keep `len` bytes at `addr` out of a core file (`MADV_DONTDUMP` on Linux, `MADV_NOCORE` on FreeBSD). Darwin has no such advice, and answers the unsupported sentinel. |
| `sysWaitWord` | value | `(-> Int Int Int)` | `IO,Unsafe` | Block while the word at byte address `addr` - 8-aligned, inside a `sysMapShared` mapping - still holds `expected`. It returns when woken, when the word already differs on entry, or spuriously, so the caller re-checks its own condition every time. That is what makes a lost wake impossible: a waker changes the word BEFORE it wakes, so a waiter that read the old value either sees the new one on entry or is already in the queue the wake empties - with one caveat on Linux, which compares only the word's low 32 bits (FUTEX_WAIT, not PRIVATE: the key is the shared page): a waiter preempted across exactly a multiple of 2^32 changes would sleep through them. Darwin compares all 64 (UL_COMPARE_AND_WAIT64_SHARED = 6). Where `waitWordKind` is 0 it returns at once and the caller spins, which is correct and costs a core. No timeout here: `sysWaitWordTimeout` below is the timed form, and it pays for the timespec this one does not need. |
| `sysWakeWord` | value | `(-> Int Int)` | `IO` | Wake every binding blocked in `sysWaitWord` on `addr`: FUTEX_WAKE (1) for INT_MAX waiters, or `__ulock_wake` with UL_COMPARE_AND_WAIT64_SHARED \| ULF_WAKE_ALL (6 \| 0x100). Answers 0 for `sysWaitWord`'s reason: a wake with nobody waiting is not an error anyone can act on. |
| `sysTimedOut` | value | `Int` |  | The `Error` code every timed operation in the concurrency modules answers when its time ran out: `chanRecvTimeout`, `chanSendTimeout`, `mutexLockTimeout`, a task past its deadline. NOT an errno: ETIMEDOUT is 60 on Darwin and FreeBSD and 110 on Linux, so a code borrowed from the kernel would need one comparison and one fixture per target. It is above 255 so that it can never be mistaken for a wait status, which is what `Task.ax` puts in the same field for a task that trapped. |
| `sysWaitWordTimeout` | value | `(-> Int Int Int Int)` | `Alloc,IO,Mut,Unsafe` | Block while the word at `addr` still holds `expected`, for at most `nanos` nanoseconds. `sysWaitWord`'s contract - an 8-aligned word in a `sysMapShared` mapping, and every answer means "re-check your own condition" - plus a bound, and an answer that says why it returned: |
| `sysTimeoutMicros` | value | `(-> Int Int)` | `Alloc,IO,Unsafe` | Microseconds from the clock a timeout is measured on: the monotonic one where the platform has it and - DELIBERATELY, since nothing better is reachable without libSystem - the realtime clock on Darwin (`clockHasMonotonic` there says why). The timed loops above this file add only non-negative steps of this clock, each clamped to the slice the kernel was asked to wait, so a step of the realtime clock moves a wait by at most one slice; MM-PAR-12 states the bound. `buf` is 16 bytes of caller scratch. A clock that cannot be read answers 0, which a caller reads as no time having passed: its wait then ends on the kernel's own timeout rather than early. |
| `sysChildPollBytes` | value | `Int` |  | Bytes of caller scratch `sysChildExited` needs: a `siginfo_t` is 104 bytes on Darwin and 128 on Linux. |
| `sysChildExited` | value | `(-> Int Int (Result Bool Error))` | `Alloc,IO,Mut,Unsafe` | Has the child `pid` ended? Without reaping it: `Ok True` means it has exited or been killed and is waiting to be reaped - so a join on it will not block - and it is STILL this process's child, still waitable, its pid not free for reuse. `Ok False` means it is running. |

## `Sys.Platform`

`stdlib/Sys/Platform.darwin.ax` — 136 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `sysRead` | value | `Int` |  | Sys.Platform - Darwin (macOS) syscall numbers and flags. |
| `sysWrite` | value | `Int` |  | write(fd, buf, count) - BSD 4 |
| `sysOpen` | value | `Int` |  | open(path, flags, mode) - BSD 5 |
| `sysClose` | value | `Int` |  | close(fd) - BSD 6 |
| `sysExit` | value | `Int` |  | exit(status) - BSD 1 |
| `sysLseek` | value | `Int` |  | lseek(fd, offset, whence) - BSD 199 |
| `openNeedsDirFd` | value | `Int` |  | Darwin has a real `open`, so no `openat` indirection is needed. `Sys.ax` branches on this rather than on an OS name, so adding a platform never means editing portable code. |
| `atFdCwd` | value | `Int` |  | Unused on Darwin (see `openNeedsDirFd`), but defined so that `Sys.ax` type-checks against every platform module. |
| `oRdonly` | value | `Int` |  |  |
| `oWronlyCreateTrunc` | value | `Int` |  | O_WRONLY \| O_CREAT \| O_TRUNC = 0x0001 \| 0x0200 \| 0x0400 |
| `oWronlyCreateAppend` | value | `Int` |  | O_WRONLY \| O_CREAT \| O_APPEND = 0x0001 \| 0x0200 \| 0x0008 |
| `seekEnd` | value | `Int` |  |  |
| `seekSet` | value | `Int` |  |  |
| `spawnUsesPosixSpawn` | value | `Int` |  | Starting a child process. |
| `sysPosixSpawn` | value | `Int` |  | posix_spawn - BSD 244. |
| `sysWait4` | value | `Int` |  | wait4(pid, status, options, rusage) - BSD 7. |
| `sysFork` | value | `Int` |  | fork() - BSD 2. `sysSpawn` does not reach it, because `spawnUsesPosixSpawn` selects `posix_spawn` here - but `sysForkProcess` does, and this used to be a placeholder 0 for that reason. |
| `sysForkArg` | value | `Int` |  |  |
| `sysExecve` | value | `Int` |  |  |
| `sysUnlinkNum` | value | `Int` |  | unlink(path) - BSD 10. |
| `sysMkdirNum` | value | `Int` |  | mkdir(path, mode) - BSD 136. Darwin has the plain call, so `openNeedsDirFd` is 0 here and `sysMkdir` uses the two-argument form. |
| `sysRmdirNum` | value | `Int` |  | rmdir(path) - BSD 137. |
| `sysRenameNum` | value | `Int` |  | rename(from, to) - BSD 128. Darwin has the plain two-argument call, so `openNeedsDirFd` is 0 here and `sysRename` uses it directly. |
| `sysGetdentsNum` | value | `Int` |  | Reading a directory. |
| `dirReadNeedsPosition` | value | `Int` |  |  |
| `direntNameOffset` | value | `Int` |  | Where the name starts inside one record. Darwin's 64-bit `dirent` is |
| `cwdUsesFcntlPath` | value | `Int` |  | The working directory. |
| `sysCwdNum` | value | `Int` |  | fcntl(fd, cmd, arg) - BSD 92. |
| `fGetPath` | value | `Int` |  |  |
| `eExist` | value | `Int` |  | The two errno values portable code above compares against. |
| `eIsDir` | value | `Int` |  |  |
| `sysGetPidNum` | value | `Int` |  | getpid() - BSD 20 |
| `sysClockNum` | value | `Int` |  | gettimeofday(tv, tz) - BSD 116. Writes {tv_sec i64, tv_usec i32+pad} to its 16-byte buffer; the register-return interpretation was probed WRONG on arm64 (x0 is 0 on success, never seconds). Verified against the shell clock, 400,000 reads, zero backwards steps, ~200ns/call. |
| `clockIsGettimeofday` | value | `Int` |  |  |
| `clockHasMonotonic` | value | `Int` |  | Whether this platform can answer a MONOTONIC clock - one that never steps backwards - through a syscall. Darwin cannot, and that is the whole reason this capability exists rather than being assumed. |
| `clockMonotonicId` | value | `Int` |  | The id `clock_gettime` is asked for the monotonic clock, where there is one. Unused here - `clockIsGettimeofday` sends both readers to `gettimeofday`, and `clockHasMonotonic` above says why - and 0 so that nobody reads a Linux number out of this file. The constant exists because the id is NOT portable: 1 is CLOCK_MONOTONIC on Linux and CLOCK_VIRTUAL, process CPU time, on FreeBSD, and `Sys.ax` carried the 1 as a literal until 2026-08-29. |
| `sysSocketNum` | value | `Int` |  | socket(domain, type, protocol) - BSD 97. |
| `sysBindNum` | value | `Int` |  | bind(fd, addr, addrlen) - BSD 104. THE ADDRLEN IS EXACT: 0, 4, 8, 12, 20, 24 and 28 were each probed and every one answered -22 EINVAL; only 16 - the size of `sockaddr_in` - returned 0. |
| `sysListenNum` | value | `Int` |  | listen(fd, backlog) - BSD 106. |
| `sysAcceptNum` | value | `Int` |  | accept(fd, addr, addrlen) - BSD 30. |
| `sysConnectNum` | value | `Int` |  | connect(fd, addr, addrlen) - BSD 98. On a non-blocking socket this answers -36 EINPROGRESS rather than failing; probed. |
| `sysSetSockOptNum` | value | `Int` |  | setsockopt(fd, level, name, val, len) - BSD 105. |
| `sysGetSockOptNum` | value | `Int` |  | getsockopt(fd, level, name, val, lenptr) - BSD 118. |
| `sysShutdownNum` | value | `Int` |  | shutdown(fd, how) - BSD 134. |
| `sysFcntlNum` | value | `Int` |  | fcntl(fd, cmd, arg) - BSD 92, and the number `sysCwdNum` above also holds. They are NOT merged: `sysCwdNum` names "the call that answers the working directory", which is `fcntl(F_GETPATH)` here and `getcwd` on Linux, and a socket has no business reading that name. |
| `afInet` | value | `Int` |  | The address family and socket type. `AF_INET` is 2 on both systems - and that agreement is a trap, because `AF_INET6` is 30 here against Linux's 10, so nothing else in this group may be assumed to match. |
| `afInet6` | value | `Int` |  | AF_INET6, AND THIS IS THE DIVERGENCE THE PARAGRAPH ABOVE WARNED ABOUT: 30 here against Linux's 10. |
| `sockStream` | value | `Int` |  |  |
| `solSocket` | value | `Int` |  | THE SOCKET-OPTION NUMBERS ARE WHERE DARWIN AND LINUX PART COMPANY, and they part completely. `SOL_SOCKET` is 0xffff here and 1 on Linux; Darwin's `SO_*` are BSD bitmask-style constants where Linux's are small sequential integers. Not one of the four below shares a value with its Linux twin, so reusing a Linux number here does not fail - it sets some other option. |
| `soReuseAddr` | value | `Int` |  |  |
| `soReusePort` | value | `Int` |  |  |
| `soError` | value | `Int` |  |  |
| `fGetFl` | value | `Int` |  | fcntl's file-status commands, and the flag a non-blocking socket sets. `O_NONBLOCK` is 4 here and 2048 on Linux. |
| `fSetFl` | value | `Int` |  |  |
| `oNonblock` | value | `Int` |  |  |
| `eAgain` | value | `Int` |  | EAGAIN, which a non-blocking `accept` or `read` answers negated when there is nothing to take yet. 35 here, 11 on Linux - so a caller that compares against a literal is correct on one target and silently wrong on the other, which is the reason this is a name. |
| `sockaddrHasLenByte` | value | `Int` |  | WHETHER `sockaddr_in` OPENS WITH A LENGTH BYTE. It does here and does not on Linux, and the two layouts cannot share a builder: |
| `pollUsesKqueue` | value | `Int` |  |  |
| `sysPollCreateNum` | value | `Int` |  | kqueue() - BSD 362. Takes no arguments. |
| `sysPollWaitNum` | value | `Int` |  | kevent(kq, changelist, nchanges, eventlist, nevents, timeout) - BSD 363, and it is BOTH of epoll's calls: `sysPollCtlNum` names the same number because registering is this call with an eventlist of nothing. |
| `sysPollCtlNum` | value | `Int` |  |  |
| `pollEventSize` | value | `Int` |  | `struct kevent` is 32 bytes on both 64-bit Darwin arches: |
| `pollEventFdOffset` | value | `Int` |  |  |
| `pollReadFilter` | value | `Int` |  | EVFILT_READ. THE ONE VALUE THAT GENUINELY DIVERGES: kqueue's filters are NEGATIVE small integers naming a kind of event, where epoll's are a positive bitmask. -1 here, EPOLLIN = 1 there. It is written into a SIGNED 16-BIT field, so `Sys.ax` masks it to two bytes rather than storing a word. |
| `pollAddOp` | value | `Int` |  | EV_ADD and EV_DELETE, which coincide with EPOLL_CTL_ADD and EPOLL_CTL_DEL at 1 and 2. The agreement is luck rather than design, so both are named on both platforms instead of being assumed. |
| `pollDelOp` | value | `Int` |  |  |
| `pollSigsetSize` | value | `Int` |  | The size of the mask argument epoll_pwait takes and kevent does not. Zero here because nothing reads it; see the Linux files for why it must be exactly 8 there. |
| `sysRandomNum` | value | `Int` |  |  |
| `randomIsGetentropy` | value | `Int` |  |  |
| `randomMaxChunk` | value | `Int` |  |  |
| `signalUsesSignalFd` | value | `Int` |  |  |
| `sysSigProcMaskNum` | value | `Int` |  | sigprocmask(how, set, oset) - BSD 48. |
| `sigBlockHow` | value | `Int` |  | SIG_BLOCK, which is 1 HERE AND 0 ON LINUX. The values are not shared and the wrong one is `SIG_UNBLOCK` on Darwin - it would unblock the signal it was asked to block, and the process would take the default disposition and die. |
| `sigsetBytes` | value | `Int` |  | Darwin's `sigset_t` is a single `__uint32_t` - FOUR bytes, against Linux's kernel `sigset_t` of eight. Nothing reads a size argument here, but the buffer's width is what the kernel copies. |
| `pollSignalFilter` | value | `Int` |  | EVFILT_SIGNAL, the filter that marks an event as a signal rather than a readable socket. Unused on Linux, where the distinction is which descriptor woke instead. |
| `sysSignalFdNum` | value | `Int` |  | Unused on Darwin (see `signalUsesSignalFd`), but defined so that `Sys.ax` type-checks against every platform module. |
| `sigInfoSize` | value | `Int` |  |  |
| `sysKillNum` | value | `Int` |  | kill(pid, sig) - BSD 37. |
| `sigTerm` | value | `Int` |  | SIGTERM and SIGINT AGREE on all four targets, which is worth naming rather than assuming because most of their neighbours do not - SIGUSR1 is 30 here and 10 on Linux. |
| `sigInt` | value | `Int` |  |  |
| `forkChildIsZero` | value | `Int` |  | Whether `fork` answers 0 in the child, which is the POSIX convention and what Linux does. Darwin answers the child's pid to both, so `sysForkProcess` normalises; see `sysFork` above for the measurement. |
| `acceptNonblockFlag` | value | `Int` |  | The flag `netAccept` passes to make the accepted socket non-blocking. Darwin's `accept` HAS no such flag - it has no `accept4` at all - so this is 0 and `Sys.ax` reaches for `fcntl` afterwards instead. |
| `usesSyscallAbi` | value | `Int` |  |  |
| `platformWriteFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc` |  |
| `platformReadFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc` |  |
| `platformExitWith` | value | `(-> Int Int)` |  |  |
| `ttyUsesTermios` | value | `Int` |  | Whether this platform's terminal control is the POSIX `termios` trio - read the attributes, edit them, write them back - reached through `ioctl`. Windows answers 0: its mechanism is `GetConsoleMode`/`SetConsoleMode` against a HANDLE, which shares no part of this shape. |
| `sysIoctlNum` | value | `Int` |  | ioctl(fd, request, arg) - BSD 54, encoded the way every number in this file is: `0x2000000 \| 54` = 33554486. Probe: `SYS_ioctl = 54 (0x36)`, `SYS_ioctl encoded = 33554486`. |
| `tcGetAttrReq` | value | `Int` |  | TIOCGETA - read the terminal attributes into a `struct termios`. |
| `tcSetAttrReq` | value | `Int` |  | TIOCSETAF - write the attributes back, after draining pending output and DISCARDING pending input. |
| `tcWinSizeReq` | value | `Int` |  | TIOCGWINSZ - read `struct winsize`. |
| `termiosBytes` | value | `Int` |  | How many bytes the kernel exchanges through the two requests above, and therefore how large a buffer a caller must hand `Sys.ax` to save a terminal's state in. |
| `termiosFlagBytes` | value | `Int` |  | The width of one flag word, which is also the STRIDE of the four of them: `c_iflag` at 0, `c_oflag` at 8, `c_cflag` at 16, `c_lflag` at 24. Probe: `c_iflag@0 c_oflag@8 c_cflag@16 c_lflag@24`, each of `size 8`. The four offsets are `n * termiosFlagBytes` on every platform this library targets, so `Sys.ax` carries one multiplication rather than four constants per module. |
| `termiosCcOff` | value | `Int` |  | Where the control-character array `c_cc` begins. Probe: `offsetof c_cc = 32 (size 20, NCCS 20)`. |
| `termiosVminIdx` | value | `Int` |  | The two `c_cc` slots that mean something once ICANON is off: how many bytes a `read` must collect before it returns, and how long it waits in tenths of a second. Probe: `VMIN = 16`, `VTIME = 17`. |
| `termiosVtimeIdx` | value | `Int` |  |  |
| `tiosEcho` | value | `Int` |  | c_lflag bits. Probe: `ECHO = 0x8 (8)`, `ICANON = 0x100 (256)`, `ISIG = 0x80 (128)`, `IEXTEN = 0x400 (1024)`. |
| `tiosIcanon` | value | `Int` |  |  |
| `tiosIsig` | value | `Int` |  |  |
| `tiosIexten` | value | `Int` |  |  |
| `tiosBrkint` | value | `Int` |  | c_iflag bits. Probe: `BRKINT = 0x2`, `ICRNL = 0x100`, `ISTRIP = 0x20`, `IXON = 0x200`. |
| `tiosIcrnl` | value | `Int` |  |  |
| `tiosIstrip` | value | `Int` |  |  |
| `tiosIxon` | value | `Int` |  |  |
| `tiosOpost` | value | `Int` |  | The one c_oflag bit raw mode touches. Probe: `OPOST = 0x1`, and it is 0x1 on Linux and FreeBSD too. |
| `sysOpenatNum` | value | `Int` |  | openat(dirfd, path, flags, mode) - BSD 463 |
| `sysSymlinkNum` | value | `Int` |  | symlink(target, link) - BSD 57 |
| `oNoFollow` | value | `Int` |  | O_NOFOLLOW = 0x100 |
| `oDirectory` | value | `Int` |  | O_DIRECTORY = 0x100000 |
| `eXdev` | value | `Int` |  | EXDEV, 18 on every kernel here: what `sysOpenBeneath` answers for a path that would leave its directory, the errno Linux's `openat2(RESOLVE_BENEATH)` answers for the same thing. |
| `sysMmapNum` | value | `Int` |  | mmap - BSD 197 (SDK sys/syscall.h), in the 0x2000000 class |
| `sysMunmapNum` | value | `Int` |  | munmap - BSD 73 |
| `mapSharedAnon` | value | `Int` |  | MAP_SHARED \| MAP_ANON = 0x1 \| 0x1000: a fork keeps these pages the SAME pages, where the arena's MAP_PRIVATE pages become copies |
| `waitWordKind` | value | `Int` |  | How a binding blocks on a shared word: 2, `__ulock_wait`/`__ulock_wake` with UL_COMPARE_AND_WAIT64_SHARED, which keys the wait on the page so a waiter and a waker in two processes over one MAP_SHARED page meet. Darwin has no futex. 1 is Linux `futex`; 0 is none (spin) |
| `sysWaitWordNum` | value | `Int` |  | __ulock_wait(op, addr, value, timeout_us) - BSD 515 (SDK sys/syscall.h) |
| `sysWakeWordNum` | value | `Int` |  | __ulock_wake(op, addr, wake_value) - BSD 516 |
| `eTimedOut` | value | `Int` |  | ETIMEDOUT - 60 here and on FreeBSD, 110 on Linux: what a timed `__ulock_wait` answers, negated, when its time ran out (`sysWaitWordTimeout`; measured -60 after a 200 ms wait). |
| `childPollKind` | value | `Int` |  | How a parent looks at a child without reaping it (`sysChildExited`): 1, `waitid` with WNOWAIT, the answer read from `si_signo`. 2 is FreeBSD's `wait6`; 0 none. |
| `sysWaitIdNum` | value | `Int` |  | waitid(idtype, id, infop, options) - BSD 173 |
| `waitIdPidType` | value | `Int` |  | P_PID - 1 here and on Linux, 0 on FreeBSD |
| `waitPollOptions` | value | `Int` |  | WEXITED \| WNOHANG \| WNOWAIT = 0x04 \| 0x01 \| 0x20 (SDK sys/wait.h) |
| `mapPrivateAnon` | value | `Int` |  | MAP_PRIVATE \| MAP_ANON = 0x2 \| 0x1000 |
| `sysMlockNum` | value | `Int` |  | mlock - BSD 203 (SDK sys/syscall.h) |
| `sysMunlockNum` | value | `Int` |  | munlock - BSD 204 |
| `sysMadviseNum` | value | `Int` |  | madvise - BSD 75 |
| `madvNoDump` | value | `Int` |  | Darwin has no madvise that keeps a range out of a core file, so 0. Core files are off unless `ulimit -c` and `kern.coredump` both allow them, and docs/crypto.md says so. |
| `randomUsesRndr` | value | `Int` |  | 0: entropy comes from the kernel call above, never from the CPU |
| `sysGetSockNameNum` | value | `Int` |  | getsockname - the address a socket is bound to |
| `sysGetPeerNameNum` | value | `Int` |  | getpeername - the address of the connected peer |
| `sysSendToNum` | value | `Int` |  | sendto - a write that takes flags, for `msgNoSignal` |
| `soRcvTimeo` | value | `Int` |  | SO_RCVTIMEO - how long a read may wait, as a struct timeval |
| `soSndTimeo` | value | `Int` |  | SO_SNDTIMEO - how long a write may wait |
| `soNoSigPipe` | value | `Int` |  | SO_NOSIGPIPE - a write to a closed peer answers EPIPE instead of raising SIGPIPE; 0 where the option does not exist |
| `msgNoSignal` | value | `Int` |  | MSG_NOSIGNAL - the same, per write, for `sendto`; 0 where the flag does not exist |
| `ipprotoTcp` | value | `Int` |  | IPPROTO_TCP - the level TCP options are set at |
| `tcpNoDelayOpt` | value | `Int` |  | TCP_NODELAY - send small writes at once rather than join them |

## `Sync`

`stdlib/Sync.ax` — 12 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Mutex` | struct |  |  | A mutex: one word, a slot in the runtime's handle table (MM-PAR-8) naming the page. |
| `MutexGuard` | struct |  |  | What a lock call answers and `mutexUnlock` takes back: one word, the serial number the acquisition drew (the module header's "the guard"). Only this module makes or reads one, and it is not `shared`. |
| `syncOwnerDead` | value | `Int` |  | Above 255, like `sysTimedOut` (1001, the timeout every lock call here answers), so none can be mistaken for a wait status. |
| `syncNotHeld` | value | `Int` |  |  |
| `syncProbeNanos` | value | `Int` |  | How long a waiter sleeps before it looks at the holder: 100 ms. |
| `mutexNew` | value | `(Result Mutex Error)` | `Alloc,IO,Mut` | A fresh mutex, free. `Err` the mapping's error, or EMFILE (24) when the handle table has no slot left. |
| `mutexLock` | value | `(-> Mutex (Result MutexGuard Error))` | `Alloc,IO,Mut` | Wait until this binding holds the lock. `Ok` the guard `mutexUnlock` wants back; `Err` code `syncOwnerDead` if the holder is found dead while this waits, or the mutex was poisoned before. |
| `mutexTryLock` | value | `(-> Mutex (Option MutexGuard))` | `IO,Mut` | Take the lock if it is free right now: `Some` the guard, `None` if it is held - or poisoned, which `mutexOwnerDead` tells apart. |
| `mutexLockTimeout` | value | `(-> Mutex Int (Result MutexGuard Error))` | `Alloc,IO,Mut,Unsafe` | `mutexLock`, waiting at most `nanos` nanoseconds. `Ok` the guard; `Err` code `sysTimedOut` when the time ran out with the lock still held by a holder that looks alive; `Err` code `syncOwnerDead` when the holder was found dead. A wait nobody ends is never shorter than `nanos` on a monotonic clock (MM-PAR-12 states Darwin's bound). A non-positive `nanos` is `mutexTryLock` with a reason. |
| `mutexUnlock` | value | `(-> Mutex MutexGuard (Result Int Error))` | `Alloc,IO,Mut` | Let the next holder in. `mg` must be the guard this binding's lock call answered: any other - on a free mutex, a stale one, a sibling's, another mutex's - is `Err` code `syncNotHeld` and leaves the lock as it was. Exactly one unlock per acquisition succeeds, however the calls interleave. |
| `mutexOwnerDead` | value | `(-> Mutex Bool)` |  | Whether a holder was found dead holding this mutex (the poisoning in the header). |
| `mutexFree` | value | `(-> Mutex (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Unmap the mutex. Only once no binding can still reach it - after the `parallel` form that used it. Takes no lock, so it is also the one safe call on a poisoned mutex. The handle is retired before the page is unmapped, so every call made after this one - a second `mutexFree` included - traps with status 85. |

## `Task`

`stdlib/Task.ax` — 17 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `TaskOpts` | struct |  |  | `width` children at most (clamped to 1..n); `limit` bytes per answer (0 or more); `deadline` nanoseconds per task from its spawn, 0 for none; `grace` nanoseconds a running task gets after a cancellation; `failFast` cancels the pool at the first error; `token` is `Some` a token from `taskTokenNew`, or `None` for one private to the call. |
| `taskOpts` | value | `(-> Int Int TaskOpts)` | `Alloc` | No deadline, a 100 ms grace, no fail-fast, a private token. |
| `taskWithDeadline` | value | `(-> TaskOpts Int TaskOpts)` | `Alloc` |  |
| `taskWithGrace` | value | `(-> TaskOpts Int TaskOpts)` | `Alloc` |  |
| `taskWithFailFast` | value | `(-> TaskOpts Bool TaskOpts)` | `Alloc` |  |
| `taskWithToken` | value | `(-> TaskOpts CancelToken TaskOpts)` | `Alloc` |  |
| `taskCancelledCode` | value | `Int` |  |  |
| `taskTooLargeCode` | value | `Int` |  |  |
| `taskPollNanos` | value | `Int` |  | How often a sleeping pool looks at its running children: 10 ms. |
| `CancelToken` | struct |  |  | A cancellation token: one word, a slot in the runtime's handle table (MM-PAR-8) naming a shared page - word 0 the cancelled flag, word 1 the event counter a pool sleeps on. |
| `taskTokenNew` | value | `(Result CancelToken Error)` | `Alloc,IO,Mut` | A fresh token, not set. `Err` the mapping's error, or EMFILE (24) when the handle table has no slot left. |
| `taskCancel` | value | `(-> CancelToken Int)` | `IO,Mut` | Set the token and wake every pool sleeping on it. Idempotent. |
| `taskCancelled` | value | `(-> CancelToken Bool)` |  | Whether the token is set: the poll a cooperative task makes. |
| `taskTokenFree` | value | `(-> CancelToken (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | Unmap a token. Only once no pool and no task can still reach it; the handle is retired first, so every call after this one - a second `taskTokenFree` included - traps with status 85. |
| `taskMap` | value | `(-> (-> Int String) Int Int Int (Vec (Result String Error)))` | `Alloc,Block,IO,Mut,Spawn` | `f i` for every `i` in `0 .. n`, at most `width` at once, each answer at most `limit` bytes: one `Result` per task in submit order. No deadline, no fail-fast, a private token. |
| `taskMapWith` | value | `(-> (-> Int String) Int TaskOpts (Vec (Result String Error)))` | `Alloc,Block,IO,Mut,Spawn` | `taskMap` with every option (`TaskOpts`). |
| `taskFold` | value | `(-> (-> Int String) Int TaskOpts Int (-> Int Int (Result String Error) Int) Int)` | `Alloc,Block,IO,Mut,Spawn,Unsafe` | Fold the answers in submit order without keeping them: `step acc i r` for each task, starting from `init`, answering the last `acc`. Each answer - and EVERYTHING `step` allocates - lives only while that `step` runs: the pool builds the answer and calls `step` inside a `region` (MM-RGN-1) that is reset when `step` returns, so memory stays flat however many tasks go through. |

## `Test`

`stdlib/Test.ax` — 8 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `Assert` | effect |  |  | The effect a failed assertion performs. |
| `assertEq` | value | `(-> String Int Int Int)` | `Alloc,Assert,IO,Mut` | Two `Int`s are equal. |
| `assertNe` | value | `(-> String Int Int Int)` | `Alloc,Assert,IO,Mut` | Two `Int`s are not equal - for the property that a value CHANGED, where naming what it changed to would pin something the test does not mean to pin. |
| `assertStrEq` | value | `(-> String String String Int)` | `Alloc,Assert,IO,Mut` | Two `String`s are equal, by bytes. |
| `assertTrue` | value | `(-> String Bool Int)` | `Alloc,Assert,IO,Mut` | A `Bool` is true. |
| `assertFalse` | value | `(-> String Bool Int)` | `Alloc,Assert,IO,Mut` | A `Bool` is false. Not `(assertTrue label (! b))`, because Axiom has no `!` and `(== b false)` at the call site is what this exists to keep out of the test. |
| `assertFloatNear` | value | `(-> String Float Float Float Int)` | `Alloc,Assert,IO,Mut` | Two `Float`s are equal within `epsilon` - the tolerance none of the assertions above need, because comparing a COMPUTED float against an exact literal is comparing against rounding error, not against the answer: `(assertEq "" 3 (+ 1 2))`'s `Int` analogue would never be wrong this way, and a `Float` one routinely is. `epsilon` is the caller's to choose rather than a default picked here, because how near is near enough depends on the computation, not on this module. |
| `testFail` | value | `(-> String Int)` | `Alloc,Assert,IO,Mut` | Fail unconditionally: the branch that must not be reached, and the case a test has not written yet. `(testFail "todo: the empty input")` reads as a failure rather than as a passing test with nothing in it, which is what an empty test body is. |

## `Tui.Edit`

`stdlib/Tui/Edit.ax` — 64 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `LED_GO` | value | `Int` |  | Keep editing. |
| `LED_DONE` | value | `Int` |  | Enter: the caller takes `ledSnapshot`. |
| `LED_EOF` | value | `Int` |  | Ctrl-D on an EMPTY buffer: end of input, the same answer the piped reader gives at EOF, so `replMain`'s farewell path is shared. |
| `LED_ABORT` | value | `Int` |  | Ctrl-C: abandon this line. NOT end of session - see the header of `term.ax` for why, and for why it cannot leave the terminal raw. |
| `LED_RING_MAX` | value | `Int` |  | How many kills the ring remembers. |
| `LineEd` | struct |  |  |  |
| `ledRingNew` | value | `(Vec String)` | `Alloc,Mut` | The kill ring, created once per session and outliving every line. |
| `ledNew` | value | `(-> (Vec String) String LineEd)` | `Alloc,Mut` | One editor over a session's ring, with the caller's word set. The gap vectors are `vecNew` (leaf) because their elements are CODE POINTS: Vec.ax's comment says a leaf block is exactly right for Ints and costs nothing. |
| `ledReset` | value | `(-> LineEd String Int Int Int)` | `Mut` | Prepare for the next physical line. Keeps both vectors' capacity. |
| `ledFree` | value | `(-> LineEd Int)` | `Unsafe` | Hand the two gap vectors back. For session end and for a test harness, which builds hundreds; see the struct's comment for why nothing else needs it. |
| `ledLen` | value | `(-> LineEd Int)` |  |  |
| `ledCursor` | value | `(-> LineEd Int)` |  | The cursor, as a code-point index. It IS `(vecLen left)`. |
| `ledCpAt` | value | `(-> LineEd Int Int)` |  | Code point `i` of the logical buffer, or 0 out of range. |
| `ledRangeStr` | value | `(-> LineEd Int Int String)` | `Alloc,Mut,Unsafe` | `cnt` code points from `s`, as a String. |
| `ledSnapshot` | value | `(-> LineEd String)` | `Alloc,Mut` | The whole buffer. This is the value handed to `replMain`, and it is the ONLY place the gap representation becomes a String - which is what keeps `replTrim`, `replParenDepth` and `replDispatch` taking exactly what they take today. |
| `ledInsert` | value | `(-> LineEd Int Int)` | `Alloc,Mut` | Insert one code point before the cursor. 1 if it went in. |
| `ledInsertStr` | value | `(-> LineEd String Int)` | `Alloc,Mut` | Decode a String and insert every code point; answers how many went in. Steps with `utf8Next`, never `utf8CharAt` in a rising loop - Utf8.ax's own comment records that as the quadratic mistake. |
| `ledSetStr` | value | `(-> LineEd String Int)` | `Alloc,Mut` | Replace the buffer, cursor at the end. What history and completion need: one call to put a whole line in. |
| `ledBackspace` | value | `(-> LineEd Int)` | `Mut` |  |
| `ledDelete` | value | `(-> LineEd Int)` | `Mut` |  |
| `ledLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` | Every motion is one code point moved from one gap vector to the other. O(1) per character; nothing re-derives the cursor. |
| `ledRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledHome` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledEnd` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledIsWord` | value | `(-> LineEd Int Bool)` |  |  |
| `ledNotWord` | value | `(-> LineEd Int Bool)` |  | The complement, as a function because Axiom has no `!` - stdlib's `assertFalse` carries the same note for the same reason. |
| `ledWordLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` | readline's rule: skip a run of non-word characters, then a run of word characters. Answers how many code points were crossed. |
| `ledWordRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledWordRightSpan` | value | `(-> LineEd Int)` |  | How many code points a forward word kill would take, WITHOUT moving the cursor - the backward kills can move and then pop, because a leftward motion pushes exactly what it crossed onto `right`, but a forward one has nowhere to put it back. |
| `ledKillPush` | value | `(-> LineEd String Int Int)` | `Alloc,Mut,Unsafe` |  |
| `ledRingIdx` | value | `(-> LineEd Int)` |  | Which ring entry a yank would take. Read by the test harness, and by whatever eventually shows the kill ring; the ring itself is the session's `Vec` and is already reachable. |
| `ledKillToEnd` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledKillToStart` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledKillWordLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` | Move left over the word, then pop what the motion pushed onto `right` - the run the cursor just crossed is exactly the top `moved` entries of that vector. |
| `ledKillWordRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  |
| `ledYank` | value | `(-> LineEd Int)` | `Alloc,Mut,Unsafe` |  |
| `ledYankPop` | value | `(-> LineEd Int)` | `Alloc,Mut,Unsafe` | Alt-y. Valid only immediately after a yank or another yank-pop, which `yankLen > 0` is exactly: every other key zeroes it in `ledApply`, so pressed cold this is a refusal that changes nothing. |
| `tuiVisLen` | value | `(-> String Int)` |  | The DISPLAY WIDTH of a string: no `ESC [ ... m` sequence counted, and no UTF-8 continuation byte counted. |
| `tuiCat` | value | `(-> (Vec String) String)` | `Alloc,Mut,Unsafe` | Every fragment in `v`, concatenated, in ONE allocation. |
| `ledCharCols` | value | `(-> Int Int)` |  | The display width of one code point. 1 for everything - see the header. The single place a wcwidth table would land. |
| `ledColsBefore` | value | `(-> LineEd Int Int)` |  | The columns the first `k` code points occupy. O(k), and it is the only reason `ledCharCols` is a function rather than a `1` written in four formulas: with a wcwidth table this stays correct and nothing else changes. |
| `ledCols` | value | `(-> LineEd Int)` |  | The width to compute with: the terminal's, or 80 when it answered something a division cannot use. A pty that has never been sized reports 0 columns with a SUCCESSFUL ioctl (Sys.ax says so), and dividing by it is the bug that report cannot make. |
| `ledContentCols` | value | `(-> LineEd Int)` |  |  |
| `ledRowOf` | value | `(-> LineEd Int Int)` |  |  |
| `ledColOf` | value | `(-> LineEd Int Int)` |  |  |
| `ledRowsUsed` | value | `(-> LineEd Int)` |  |  |
| `ledCup` | value | `(-> Int Int String)` | `Alloc,Mut,Unsafe` | `ESC [ n <final>`, or "" when n < 1 so a zero-distance move costs no bytes. 65 A up, 66 B down, 67 C forward, 68 D back. |
| `ledClearScreen` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | `ESC [ H ESC [ 2 J` - cursor home, erase the whole screen. Ctrl-L. |
| `ledEraseRow` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | `ESC [ 0 K` - erase from the cursor to the end of the row. Spelled out rather than routed through `ledCup`, which refuses n < 1 and would answer "" - an erase that emits nothing is a redraw that leaves the old line's tail on the screen. |
| `ledEraseOld` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut` | Erase what the previous refresh drew and leave the cursor at column 0 of the first row. |
| `ledRefreshFull` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut,Unsafe` | The multi-row repaint. |
| `ledRefreshWindow` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut,Unsafe` |  |
| `ledRefresh` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut` | The one dispatcher, so the choice between the two repaints lives in exactly one place. |
| `ledRefreshFullPainted` | value | `(-> LineEd (Vec String) String Int)` | `Alloc,Mut,Unsafe` |  |
| `ledRefreshPainted` | value | `(-> LineEd (Vec String) String Int)` | `Alloc,Mut` | Like `ledRefresh`, but the full repaint draws `painted` - the caller's rendering of the current buffer - instead of the plain snapshot. See `ledRefreshFullPainted` for the width contract that makes the cursor land correctly. |
| `ledResize` | value | `(-> LineEd Int Int Int)` | `Mut` | Called with the terminal's current size before every refresh. When the width changed we cannot know how the terminal reflowed the text it already holds, so `rows` and `curRow` are reset rather than used: refusing to compute motions from a stale width beats computing them wrongly, and one more keystroke fully repairs the line. 1 when it changed. |
| `ledApply` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` |  |
| `ledIsKillKey` | value | `(-> KeyEv Bool)` |  |  |
| `ledIsYankKey` | value | `(-> KeyEv Bool)` |  |  |
| `ledByWord` | value | `(-> KeyEv Bool)` |  | A motion key carrying Ctrl or Alt is the WORD variant. Terminals disagree about which modifier they send for Ctrl-Left - xterm sends MOD_CTRL, several send MOD_ALT, and Alt-b is the same motion by another name - so both are accepted rather than one being picked. |
| `ledDispatch` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` |  |
| `ledNavKey` | value | `(-> LineEd KeyEv Int)` | `Alloc,Mut` | Arrows, Home and End - and the keys this effort deliberately leaves alone. Up and Down belong to the HISTORY effort and Tab to COMPLETION; they are decoded, they arrive here, and they do nothing. Adding them is a branch beside these, not a change to the decoder. |
| `ledCharKey` | value | `(-> LineEd KeyEv Int)` | `Alloc,Mut` | A printable key, or an Alt-<letter> word command. Alt-b/f/d/y are the bindings every terminal can produce, where Ctrl-Left and Alt-Delete are the ones only some can. |
| `ledCtrlKey` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` | The control keys. readline's letters, and only the ones this effort owns: Ctrl-N and Ctrl-P are history's and are left unbound so that effort can take them without moving anything here. |

## `Tui.Keys`

`stdlib/Tui/Keys.ax` — 43 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `KEY_NONE` | value | `Int` |  | The event was consumed and means nothing to the editor - a mouse report, a device reply, a stray byte. It is NOT "nothing happened": `used` is still the bytes to advance by. |
| `KEY_MORE` | value | `Int` |  | A strict prefix. Read more, or resolve it with `keyResolve`. This kind never leaves `term.ax`. |
| `KEY_EOF` | value | `Int` |  |  |
| `KEY_CHAR` | value | `Int` |  | `cp` is the code point. |
| `KEY_CTRL` | value | `Int` |  | `cp` is the LETTER, 64..95: Ctrl-A is 65, Ctrl-@ is 64, Ctrl-_ is 95. Storing the letter rather than the control byte is what lets the binding table read as `(== ev.cp 65)` beside a comment saying A. |
| `KEY_ENTER` | value | `Int` |  |  |
| `KEY_TAB` | value | `Int` |  |  |
| `KEY_BACKSPACE` | value | `Int` |  |  |
| `KEY_ESCAPE` | value | `Int` |  |  |
| `KEY_UP` | value | `Int` |  |  |
| `KEY_DOWN` | value | `Int` |  |  |
| `KEY_RIGHT` | value | `Int` |  |  |
| `KEY_LEFT` | value | `Int` |  |  |
| `KEY_HOME` | value | `Int` |  |  |
| `KEY_END` | value | `Int` |  |  |
| `KEY_DELETE` | value | `Int` |  |  |
| `KEY_INSERT` | value | `Int` |  |  |
| `KEY_PGUP` | value | `Int` |  |  |
| `KEY_PGDN` | value | `Int` |  |  |
| `KEY_FN` | value | `Int` |  | `cp` is the function-key number: KEY_FN with cp 5 is F5. |
| `MOD_SHIFT` | value | `Int` |  |  |
| `MOD_ALT` | value | `Int` |  |  |
| `MOD_CTRL` | value | `Int` |  |  |
| `keyCsiMax` | value | `Int` |  | How many bytes of a well-formed CSI this decoder will tolerate before calling it line noise. A wedged terminal spewing digits cannot otherwise grow the pending prefix without bound. |
| `keyStrMax` | value | `Int` |  | And of an OSC/DCS string body. |
| `KeyEv` | struct |  |  |  |
| `keyScanCtrl` | value | `(-> Int KeyEv)` | `Alloc` |  |
| `keyCsiEnd` | value | `(-> String Int Int Int)` |  |  |
| `keyCsiParam` | value | `(-> String Int Int Int Int)` |  |  |
| `keyCsiPrivate` | value | `(-> String Int Int Bool)` |  | A CSI whose first parameter byte is `<`, `=`, `>` or `?` is a private form: a mouse report, a device-attributes reply, a mode report. None of them is a keystroke. |
| `keyTildeKind` | value | `(-> Int Int)` |  | The key a `~`-final CSI names, from its first parameter. |
| `keyTildeFn` | value | `(-> Int Int)` |  | F1..F12 out of a `~`-final parameter, or 0 for one that names none. |
| `keyFinalKind` | value | `(-> Int Int)` |  | The key a letter-final CSI or SS3 names. |
| `keyFromCsi` | value | `(-> String Int Int Int KeyEv)` | `Alloc` |  |
| `keyFromSs3` | value | `(-> String Int Int KeyEv)` | `Alloc` |  |
| `keyStrEnd` | value | `(-> String Int Int Int)` |  |  |
| `keyScanUtf8` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` |  |
| `keyScan` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` |  |
| `keyScanEsc` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` | The escape path. See the header for the case list. |
| `keyScanCsi` | value | `(-> String Int Int KeyEv)` | `Alloc` |  |
| `keyScanStr` | value | `(-> String Int Int KeyEv)` | `Alloc` |  |
| `keyScanAlt` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` | ESC <anything else> is Alt-that-key: decode the key at off+1 and OR MOD_ALT into it. `used` grows by the ESC. |
| `keyResolve` | value | `(-> String Int Int KeyEv)` | `Alloc` |  |

## `Tui.Term`

`stdlib/Tui/Term.ax` — 13 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `termBufBytes` | value | `Int` |  | One `read` takes up to this much. Large enough that a pasted line arrives in one syscall, which is what makes the redraw coalescing below turn a paste into roughly one repaint. |
| `keyEscTimeoutMs` | value | `Int` |  | How long to wait for the rest of an escape sequence before deciding there is no rest. |
| `mkKeyIn` | value | `(-> Int Int KeyIn)` | `Alloc,IO,Mut,Unsafe` | A reader over `fd`. `active` 0 builds the inert shape: no poll descriptor, a one-byte buffer, and nothing ever read - which is what the piped path gets, so that the byte-identical surface pays for none of this. |
| `keyInPending` | value | `(-> KeyIn Int)` |  | Bytes read but not yet consumed. The redraw coalescing asks this. |
| `keyInFill` | value | `(-> KeyIn Int Int)` | `Alloc,IO,Mut,Unsafe` |  |
| `keyNext` | value | `(-> KeyIn KeyEv)` | `Alloc,IO,Mut` |  |
| `termReadSize` | value | `(-> KeyIn Int)` | `IO,Mut,Unsafe` | Refresh `kin.ws` from the terminal. One ioctl; there is no SIGWINCH handling anywhere in this tree, so the size is asked for rather than delivered. |
| `termWsCols` | value | `(-> KeyIn Int)` | `Unsafe` | Columns, or 80. A pty that has never been sized answers 0 with a SUCCESSFUL ioctl - Sys.ax states it - so the fallback is on the VALUE and not only on the return code. |
| `termWsRows` | value | `(-> KeyIn Int)` | `Unsafe` |  |
| `termRawEnter` | value | `(-> KeyIn Int)` | `Alloc,IO,Mut,Unsafe` | Enter raw mode on fd 0, saving into `kin.save`. 0, or negative. `keepSignals` 0: see the header. |
| `termRawLeave` | value | `(-> KeyIn Int)` | `IO,Unsafe` |  |
| `termFlush` | value | `(-> (Vec String) Int)` | `Alloc,IO,Mut` |  |
| `termEditLoop` | value | `(-> KeyIn LineEd String (Option String))` | `Alloc,IO,Mut` |  |

## `Utf8`

`stdlib/Utf8.ax` — 13 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `utf8IsCont` | value | `(-> Int Bool)` |  | Is `b` a continuation byte, `10xxxxxx`? |
| `utf8SeqLen` | value | `(-> Int Int)` |  | How many bytes the sequence beginning with lead byte `b` occupies. |
| `utf8DecodeAt` | value | `(-> String Int (Option Int))` |  | The code point whose encoding begins at byte offset `i`, or `None` when there is none there. |
| `utf8Next` | value | `(-> String Int Int)` |  | The byte offset of the character after the one beginning at `i`, clamped to the byte length - `utf8Offset` clamps, and two stepping functions that disagree about the end of a string is a trap. |
| `utf8Len` | value | `(-> String Int)` |  | The number of code points in `s`. |
| `utf8Offset` | value | `(-> String Int Int)` |  | The byte offset at which character `n` begins, or the byte length of `s` when there are fewer than `n` characters. |
| `utf8CharAt` | value | `(-> String Int (Option Int))` |  | Character `n` of `s`, counting from 0. `None` past the end, the same answer `utf8DecodeAt` gives a byte it cannot decode and for the same reason. The tail call FORWARDS `utf8DecodeAt`'s two registers as they arrive (`pairFwdOK`), so this keeps `no-alloc` on the same terms. |
| `utf8Slice` | value | `(-> String Int Int String)` | `Alloc,Mut` | `count` characters of `s` beginning at character `start`, as a `Str` sharing the original's bytes - the character-indexed counterpart of `strSlice`. |
| `utf8Replacement` | value | `Int` |  | U+FFFD REPLACEMENT CHARACTER, what a code point that cannot be encoded becomes. |
| `utf8Width` | value | `(-> Int Int)` |  | How many bytes code point `cp` occupies when encoded - counting what `utf8FromChar` will actually write, so the two never disagree. |
| `utf8FromChar` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` | A freshly allocated `Str` holding `cp` alone. |
| `utf8Valid` | value | `(-> String Bool)` |  | Is every byte of `s` part of a well-formed UTF-8 sequence? |
| `utf8WellFormedAt` | value | `(-> String Int Int Int)` |  | The length of the WELL-FORMED UTF-8 sequence that begins at byte `i` of `s` and ends at or before byte `end`: 1 to 4, or 0 when the bytes there are not one. |

## `Vec`

`stdlib/Vec.ax` — 23 public names

| Name | Kind | Type | Effects | Summary |
|---|---|---|---|---|
| `vecNew` | value | `(Vec a)` | `Alloc,Mut` | An empty `Vec` with `vecDefaultCap` capacity. |
| `vecWithCapacity` | value | `(-> Int (Vec a))` | `Alloc,Mut` | An empty `Vec` that can hold at least `cap` elements without growing. |
| `vecWithCapacityRef` | value | `(-> Int (Vec a))` | `Alloc,Mut` | The same, with an ARRAY-FORM data block: every element is a handle this vector owns a share of. See the module comment. |
| `vecNewRef` | value | `(Vec a)` | `Alloc,Mut` | An empty `Vec` with `vecDefaultCap` capacity, owning its elements. |
| `vecFree` | value | `(-> (Vec a) Int)` | `Unsafe` | Hand `v` back. Its data block goes with it - the header's reference map names word 2 - and, for a `vecNewRef` vector, so does one share of every element. The caller must own the share being released and must not reuse the handle or its data after its last share is released. |
| `vecOwnsRefs` | value | `(-> (Vec a) Bool)` | `Unsafe` | Whether this vector owns a share of every element it holds - the `vecNewRef` half of the module comment. It is word 3 of the header and not a test of the data block's shape word: see `vecBuild`. |
| `vecLen` | value | `(-> (Vec a) Int)` | `Unsafe` |  |
| `vecCap` | value | `(-> (Vec a) Int)` | `Unsafe` |  |
| `vecGet` | value | `(-> (Vec a) Int a)` | `Unsafe` | The element at `i`. REFUSES an index outside `0 .. (vecLen v) - 1`. |
| `vecTry` | value | `(-> (Vec a) Int (Option a))` | `Alloc,Unsafe` | The element at `i`, or `None` when there is no element at `i`. |
| `vecGetStr` | value | `(-> (Vec a) Int String)` | `Unsafe` |  |
| `vecGetVec` | value | `(-> (Vec a) Int (Vec b))` | `Unsafe` | The element at `i` read back as a CONTAINER. |
| `vecPushStr` | value | `(-> (Vec a) String (Vec a))` | `Alloc,Mut,Unsafe` | Append a `String` to a vector of WORDS, keeping the share. |
| `vecPushVec` | value | `(-> (Vec a) (Vec b) (Vec a))` | `Alloc,Mut,Unsafe` | The same for a nested container. A `Vec` handle is a counted block too, so it needs the same explicit share for the same reason. |
| `vecSet` | value | `(-> (Vec a) Int a (Vec a))` | `Mut,Unsafe` | Overwrite the element at `i`. Returns the handle. |
| `vecPush` | value | `(-> (Vec a) a (Vec a))` | `Alloc,Mut,Unsafe` | Append `x`. Returns the handle - the same one, with this representation; see the module comment for why it is returned anyway. |
| `vecPop` | value | `(-> (Vec a) a)` | `Mut,Unsafe` | Remove and return the last element. REFUSES an empty vector. |
| `vecLast` | value | `(-> (Vec a) a)` |  | The last element without removing it. REFUSES an empty vector. |
| `vecClear` | value | `(-> (Vec a) (Vec a))` | `Mut,Unsafe` | Drop every element, keeping the capacity. Returns the handle. |
| `vecSum` | value | `(-> (Vec Int) Int)` |  | The sum of every element. |
| `vecHash` | value | `(-> (Vec Int) Int)` |  | A position-sensitive digest of the whole vector. |
| `vecSort` | value | `(-> (Vec a) (Vec a))` | `Mut,Unsafe` | Sort ascending, in place, by machine word. Answers the vector. |
| `vecSortBy` | value | `(-> (Vec a) (-> Int Int Int) (Vec a))` | `Mut,Unsafe` | The same, ordered by a caller's comparison rather than by the word. |

