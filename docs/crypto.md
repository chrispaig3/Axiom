# Cryptography

Axiom's standard library includes a cryptography suite written in
Axiom. It links nothing extra and adds no C library, so a program that
encrypts or signs still builds from the same freestanding toolchain as
any other. This page shows how to use it, what each part promises, and
where its limits are.

```scheme
(import IO)
(import Err)
(import Crypto.Random)
(import Crypto.Secret)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (secretRandom 32)
    ((Ok key)
      {
        (println "{key}")
        (println (secretLen key))
        (secretWipe key)
        0
      })
    ((Err e) (die (errorText e) 1))))
```

```text
<SecretBytes>
32
```

The key never reaches the output. A secret prints as its type's name,
and `secretWipe` erases it when you are done.

## Random values

`Crypto.Random` answers secure random values from the operating
system's kernel on every call:

| Call | Answers |
|---|---|
| `(secureRandomBytes n)` | `n` random bytes |
| `(randomBelow n)` | an `Int` in `0` to `n - 1`, each value equally likely |
| `(randomRange lo hi)` | an `Int` in `lo` to `hi - 1` |
| `(randomShuffle v)` | shuffles a `Vec` in place into a uniformly random order |
| `(randomTokenUrl n)` | `n` random bytes as URL-safe base64, for tokens and identifiers |
| `(randomTokenHex n)` | `n` random bytes as lower-case hex |

Each one answers a `Result`. The source is `getentropy` on Darwin and
`getrandom` on Linux and FreeBSD. On `baremetal-aarch64` it is the
CPU's `RNDR` register when the CPU has one. There's no generator
inside your program, so there is no seed to manage, nothing a `fork`
duplicates, and nothing threads share.

There's no fallback either. When the kernel call fails, or the target
has no secure source, you get `Err` with code `cryptoEntropyFailed` or
`cryptoEntropyUnavailable`. Nothing substitutes a clock, a process id
or a counter. `randomAvailable` tells you ahead of time whether this
target has a source.

`randomBelow` rejects draws outside the range rather than reducing
them with `%`, so small values aren't favoured. A token needs at least
16 bytes (128 bits) to be unguessable.

Random values are not unique values. Two random 96-bit nonces collide
with probability about n²/2⁹⁷ after n messages, so an authenticated
cipher sets a limit on how many random nonces one key may use.

Tested by `tests/crypto/020-random.ax`.

## Keys and secrets

A secret is a handle, not a buffer. `SecretBytes` and every key type in
the suite are sealed: only the module that declares the type can make
one or read what's inside. A secret prints as `<SecretBytes>`, so it
can't reach a log line, a `Json` value or a formatted string by
accident. One algorithm's key type can't be passed where another's is
expected.

```scheme fragment
(secretRandom 32)          ; a fresh random secret
(secretFromString bytes)   ; a secret holding a copy of these bytes
(secretEq a b)             ; compares in constant time
(secretWipe k)             ; erases and frees it
(secretExposeCopy k)       ; a plain copy, for writing a key out
```

Each secret lives in a memory mapping of its own, outside the arena,
so a region reset can't reclaim it while you still hold it. The suite
asks the kernel to keep that mapping out of swap (`mlock`) and, on
Linux and FreeBSD, out of core files. Both requests can be refused: an
unprivileged process may lock only a few megabytes. The secret still
works when they are, and `(secretIsLocked k)` tells you which you got.

`secretWipe` overwrites the whole mapping with zeros in a way the
optimiser can't remove, then unmaps it. Using a secret after wiping it
stops the program with status 85, and so does passing one key type's
handle where another's is expected. The suite wipes every temporary it
derives from a secret, such as a key schedule, before it returns.

Erasure has limits you should know:

- A copy you made with `secretExposeCopy` is an ordinary string. The
  suite can't find it to wipe it.
- Values that were in registers or on the stack while an operation ran
  aren't cleared.
- A `parallel` binding that runs in a forked child gets a copy of every
  secret mapping, and wiping in the parent doesn't reach it.
- A secret you never wipe stays mapped until the program exits. There
  is no destructor.

Tested by `tests/crypto/030-secret.ax` and
`tests/stdlib/640-crypto-secret-wiped.ax`.

## Byte strings

A `String` holds any bytes, so the suite uses it for public byte data:
messages, ciphertexts, digests and encoded keys. `Crypto.Bytes` has
what you need around them:

- `bytesEqCt` compares two strings in time that depends only on their
  lengths. Use it, never `==`, for tags and digests of secrets.
- `hexEncode` and `hexDecode`, `b64Encode` and `b64Decode`, and the
  unpadded and URL-safe variants, run in constant time.
- The decoders are strict. A character outside the alphabet, padding
  in the wrong place, or leftover bits that aren't zero is an `Err`, so
  every byte string has exactly one accepted encoding.
- `bytesU32Be`, `bytesU64Le` and their kin encode integers.

Tested by `tests/crypto/010-bytes.ax`.

## Authenticated encryption

An authenticated cipher keeps a message secret and detects any change
to it. The suite has AES-256-GCM, AES-128-GCM and ChaCha20-Poly1305,
each with the same shape:

```scheme
(import IO)
(import Str)
(import Err)
(import Crypto.Aead)
(import Crypto.AesGcm)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match aes256GcmKeyGenerate
    ((Err e) (die (errorText e) 1))
    ((Ok key)
      (match aeadNonceRandom
        ((Err e) (die (errorText e) 1))
        ((Ok nonce)
          (let ((sealed (unwrapOr (aes256GcmSeal key nonce "order 17" "attack at dawn") "")))
            {
              (println (strLen sealed))
              (match (aes256GcmOpen key nonce "order 17" sealed)
                ((Ok plain) (println plain))
                ((Err e) (println (errorText e))))
              (match (aes256GcmOpen key nonce "order 18" sealed)
                ((Ok plain) (println plain))
                ((Err e) (println (errorText e))))
              (aes256GcmKeyWipe key)
              0
            }))))))
```

```text
30
attack at dawn
authentication failed while aes256GcmOpen
```

`Seal` takes the key, a nonce, associated data and the plaintext, and
answers the ciphertext with a 16-byte tag on the end. The associated
data isn't encrypted, but it is authenticated: opening with different
associated data fails, as the third call shows. Use it for whatever
the ciphertext must stay bound to, such as a record id or a header.

`Open` checks the tag before it decrypts anything, so no plaintext is
released from a message that fails. Every failure, whether a wrong key,
a changed byte, a truncated tag or the wrong associated data, answers
the same `cryptoAuthFailed` error.

| Module | Key | Nonce | Tag | Longest plaintext |
|---|---|---|---|---|
| `Crypto.AesGcm` | `Aes256GcmKey` or `Aes128GcmKey` | 12 bytes | 16 bytes | 2³⁶ − 32 bytes |
| `Crypto.ChaCha20Poly1305` | `ChaCha20Poly1305Key` | 12 bytes | 16 bytes | 274,877,906,880 bytes |

Prefer AES-256-GCM where you need a NIST-approved algorithm and
ChaCha20-Poly1305 otherwise. Both run in constant time here: AES is
bitsliced, with no lookup table indexed by a secret. Only one-shot
calls exist, so a message is sealed or opened whole.

Tested by `tests/crypto/220-aes-gcm.ax` and
`tests/crypto/250-chacha20-poly1305.ax`.

### Nonces

A nonce must never repeat under one key. A repeat under GCM reveals
the XOR of two plaintexts and lets an attacker forge tags, so this is
the one rule you can't get wrong. You have two ways to follow it:

- `aeadNonceRandom` draws 12 random bytes. Use at most 2³² of them
  with one key (NIST SP 800-38D section 8.3); past that, the chance of
  a repeat is too high. Rotate the key before then.
- `NonceSequence` counts. `(nonceSequenceNew prefix)` takes a 4-byte
  prefix unique to this sender, and each `nonceSequenceNext` answers
  the next nonce or `cryptoLimitExceeded` once the counter runs out.
  It never wraps.

A sequence is only as unique as its counter. If your program restarts,
resume with `nonceSequenceResume` from a position you saved, and save
the position *before* you seal with the nonce it answers, so a crash
between the two can't make you reuse one. Two processes sharing a key
need different prefixes.

Tested by `tests/crypto/260-aead-nonce.ax`.

## Constant time

A function runs in constant time when nothing an attacker can time
depends on a secret: which branches run, which memory it touches, and
which instructions it uses. The suite's code avoids branches, memory
indices and division that depend on secrets.

Code that looks branchless isn't enough, because the optimiser can
turn a mask back into a branch. `Crypto.Ct` passes every mask a secret
produces through `ctBarrier`, an empty assembly block that hides the
value from the optimiser. Functions that handle secrets carry a
`;@axiom:ct(...)` tag naming their secret parameters.

Some channels are below what Axiom source controls: a multiplier whose
timing depends on its operands, cache lines shared with another
process, and speculative execution. The suite removes the channels
software can see. It can't promise more than the processor does.

In particular, GHASH, Poly1305 and the curve and lattice arithmetic
rely on 64-bit multiplication taking the same time for every operand.
Arm promises that only while the DIT bit (FEAT_DIT) is set, and the
suite doesn't set it yet.

`scripts/check-crypto.sh` checks every claimed kernel's optimised IR
at `--opt` 1, 2 and 3 for a branch, a `select`, a memory index or a
division that depends on a secret. A timing measurement would only be
supporting evidence, so there's no timing test in the gate.

## Performance

Measured on darwin-aarch64 at `--opt 1`: whole-process time over many
iterations, best of five, with an empty program's startup subtracted.

| Operation | 1 MiB | 64-byte message |
|---|---|---|
| AES-256-GCM seal | 111 MB/s | 1.42 µs |
| AES-256-GCM open | 97 MB/s | 1.53 µs |
| AES-128-GCM seal | 130 MB/s | 1.14 µs |
| ChaCha20-Poly1305 seal | 226 MB/s | 0.90 µs |
| ChaCha20-Poly1305 open | 217 MB/s | 0.96 µs |

## Error codes

Every Crypto module answers an `Err` carrying one of these codes:

| Code | Name | Means |
|---|---|---|
| 1101 | `cryptoInvalidLength` | a key, nonce, tag, salt or input of a length the algorithm doesn't accept |
| 1102 | `cryptoInvalidEncoding` | bytes that don't decode, or a key or signature that isn't a canonical encoding |
| 1103 | `cryptoAuthFailed` | authentication failed; no plaintext is released |
| 1104 | `cryptoEntropyUnavailable` | this target has no secure entropy source |
| 1105 | `cryptoEntropyFailed` | the kernel's entropy call failed |
| 1106 | `cryptoLimitExceeded` | a usage limit, such as a message length or a nonce sequence that has run out |
| 1107 | `cryptoUnsupported` | parameters this implementation doesn't support |
| 1108 | `cryptoNoSecretStore` | the kernel refused a mapping for a secret, or the handle table is full |
| 1109 | `cryptoInvalidKey` | a key that decodes but must not be used |

Every authentication failure answers the same code and message, so an
error never tells an attacker which check a forgery failed.

## Limits

- Not yet on `windows-x86_64`: there's no entropy source or secret
  store there, and each call answers an availability error.
- On `baremetal-aarch64` there's no page mapping for the secret store,
  so key types aren't available there yet. Random values are, on CPUs
  with `RNDR`.
- The suite hasn't had an external cryptographic review, and it isn't
  a FIPS 140-3 validated module.

## See also

- [stdlib-api.md](stdlib-api.md) lists every public name in the
  `Crypto` modules with its type and effects.
- [memory-model.md](memory-model.md) `MM-PAR-8` describes the handle
  table that the secret store's handles live in.
