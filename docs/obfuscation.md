# Optional binary obfuscation

Axiom can make a binary harder to inspect statically. Choose the
compiler mode for source literals and internal function names, and
`Crypto.Obfuscate` for assets packed before compilation. Both are
optional. A developer who can inspect the running process can recover
embedded keys and decoded data.

## Build an obfuscated executable

```bash
axiom build Main.ax --obfuscate --opt 3 -o app
```

`--obfuscate` draws fresh build seeds from the operating system. It
masks every emitted Axiom string literal, including imported modules,
and decodes the bytes before the user entry point runs. Strings keep
their lengths, NUL terminators and static lifetime. The mask uses a
xorshift32 stream with split volatile seeds. It conceals literals from
tools such as `strings`; it is not cryptographic protection for secrets.

The compiler replaces defined function names with build-specific
identifiers, strips local linker symbols, and adds opaque entry
branches through distinct helpers with volatile reads. Optimisation
keeps these branches. These are entry transformations; the mode does
not flatten every branch of a function. It preserves the platform
entry points and the `axiom_*` runtime ABI used by linked Rust code.
External declarations and names inside separately linked archives
retain their ABI spelling.

Obfuscated builds omit the source-level backtrace tables, which would
otherwise disclose function names and source paths. Traps still report
their messages and exit statuses. Startup decoding costs time and
writable storage proportional to the literals, and the opaque entries
add work to calls. Each build differs; ordinary builds retain their
existing reproducibility behaviour.

The flag works with `build`, `run` before the file operand, and
`emit-llvm` for a program with a `main`. Static archives are refused
because they need a host-controlled initialisation contract. A flag
after `run FILE` belongs to the program, as other program arguments do.
`--emit-llvm` retains the transformed IR; distribute the executable
according to your project's artifact policy.

Tested by `scripts/check-obfuscation.sh`: execution and plaintext
absence at optimisation levels 0, 1 and 3, ordinary-build ablation,
fresh build seeds, O3 branch retention, and assembly for all targets.
Cross-target assembly does not establish cross-target execution.

## Pack an embedded asset

Build the packing tool once, then run it before compiling the
application. The input can contain arbitrary bytes.

```bash
axiom build examples/axobfuscate/Main.ax -o axobfuscate
./axobfuscate resources/message.bin Packed.ax 'my-app/message/v1'
axiom build Main.ax --obfuscate -o app
```

Keep `Packed.ax` beside `Main.ax`, or place it on your module search
path. Each packing run generates a fresh master key, two random XOR
shares and a fresh envelope nonce. The generated module contains hex
encoded shares, context and ciphertext. Its `openAsset` returns the
authenticated plaintext as `(Result String Error)` and wipes its
temporary master key. The application imports only the packed module;
including the original plaintext as a source literal would expose that
copy in an ordinary build.

```scheme
(import IO)
(import Err)
(import Crypto.Obfuscate)

(:: roundTrip (-> ObfuscationKey (Result String Error)))
;@axiom:effect(io)
;@axiom:effect(entropy)
(fn (roundTrip key)
  (match (obfuscationSeal key "example/asset/v1" "embedded text")
    ((Err e) (Err e))
    ((Ok envelope) (obfuscationOpen key "example/asset/v1" envelope))))

(:: main (Result Int Error))
;@axiom:effect(io)
;@axiom:effect(entropy)
(fn (main)
  (match obfuscationKeyGenerate
    ((Err e) (Err e))
    ((Ok key)
      (let ((opened (roundTrip key)))
        {
          (obfuscationKeyWipe key)
          (match opened
            ((Err e) (Err e))
            ((Ok bytes) { (println bytes) (Ok 0) }))
        }))))
```

For a generated asset, replace `roundTrip` with the packed module's
`openAsset`. The [asset fixture](../tests/obfuscation/AssetUser.ax)
shows the importing application. Repack for each distributed build.
The two shares together reveal the master key; their purpose is to
avoid storing its contiguous bytes in the binary.

## Envelope and key contracts

`ObfuscationKey` is a sealed 32-byte key held by `Crypto.Secret`.
`obfuscationKeyGenerate` draws a new one,
`obfuscationKeyFromSecret` copies a 32-byte secret, and
`obfuscationKeyFromShares` XORs two 32-byte strings directly into the
secret store. `obfuscationKeyWipe` retires the key. All copies of a
retired handle become unusable.

A v1 envelope contains the eight bytes `AXOBv1\0\0`, a 12-byte random
nonce, ciphertext, and a 16-byte ChaCha20-Poly1305 tag. HKDF-SHA-256
derives the AEAD key from the master key with the nonce as salt. Its
info is `Axiom.Obfuscate.v1\0`, the context's eight-byte big-endian
length, and the context. Associated data contains the header and nonce,
then the same length-prefixed context. Use distinct contexts for assets
with distinct purposes. Seal at most 2³² envelopes under one master
key; the packing tool uses a fresh key for every asset.

Assets are at most 64 MiB and contexts at most 4096 bytes. Opens check
the tag before returning plaintext. A changed key, context, nonce,
ciphertext or tag answers `cryptoAuthFailed`. Incomplete or unknown
headers answer `cryptoInvalidEncoding`; inputs above the limits answer
`cryptoLimitExceeded`. Derived keys are wiped on both success and error.
Returned plaintext is an ordinary `String`.

Tested by `tests/crypto/330-obfuscate.ax` and
`scripts/check-obfuscation.sh`. The underlying primitives retain their
[cryptography contracts](crypto.md).
