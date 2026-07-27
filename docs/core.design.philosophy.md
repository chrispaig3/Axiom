# Core Design Philosophy

## 1. Symbolic Computation

***Axiom is not "Rust with pretty syntax", "Haskell for agents", or "Lisp with memory management".***

Its core identity is:

**Code is symbolic structure.** Computation is transformation of symbolic structure.

This is why AXSYM feels natural — it's the language's true center.

Everything else (types, effects, agents, memory) must align with this.

This is why:

- macros make sense
- transformations make sense
- pipelines make sense
- AST rewriting feels native
- region syntax feels wrong
- C-FFI feels wrong

Axiom is a symbolic language, not a pointer language.

## 2. Agents as First-Class Computational Entities

Axiom is the first language where agents aren't a library — they're a semantic primitive.

Agents in Axiom:

- sense
- decide
- act
- transform state
- hold capabilities
- operate under effects
- compose pipelines

This is why your instinct to build an Agent Effect System (AES) is correct.

Axiom is not "FP with actors." It's symbolic computation shaped around agents.

## 3. Transformations Instead of Control Flow

Axiom rejects:

- loops
- iterators
- imperative control flow
- procedural APIs

Instead, everything is:

```
code |> transform |> transform |> transform
```

This is not a stylistic choice; it's a philosophical one.

Axiom believes: **Computation is composition, not instruction.**

This is why:

- pipelines feel right
- macros feel right
- symbolic regions feel right
- effect typing feels right
- Rust interop feels right

And why:

- C-FFI feels wrong
- region lifetimes feel wrong
- imperative memory feels wrong

## 4. Minimalism with Power

Axiom is intentionally small.

Not "small because it's unfinished," but "small because it's designed that way."

Axiom wants:

- a tiny core
- a tiny type system
- a tiny effect system
- a tiny memory model
- a tiny module system
- a tiny stdlib (or none)

But each piece must be:

- expressive
- composable
- symbolic
- agent-native
- transformation-centric

This is why you keep rejecting:

- GC
- borrow checker
- region syntax
- giant stdlib
- heavy typeclasses
- monads
- async/await

Axiom is a precision instrument, not a kitchen sink.

## 5. Deterministic, Explicit Resource Control

This is where your "no GC, no runtime" instinct fits.

Axiom believes:

- Agents must explicitly control resources. Nothing should happen behind the user's back.

This leads naturally to:

- manual memory via symbolic regions
- linear capabilities
- effect typing
- agent-controlled allocation
- deterministic behavior
- zero hidden costs

This is why Rust interop fits and C-FFI does not. Rust gives you deterministic, explicit resource control. C gives you chaos.
