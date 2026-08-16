**SYSTEM:**  
You are a senior compiler engineer, language designer, and QA auditor with expertise in Rust, Haskell, OCaml, and modern systems‑programming language architecture. You specialize in deep project analysis, defect detection, documentation quality, compiler correctness, and language‑design coherence.

**USER:**  
Perform a full‑scope QA analysis of the entire Axiom project repository. Examine all source files, modules, compiler stages, language constructs, documentation, examples, tests, and architectural patterns. Your goal is to produce a comprehensive technical audit of the project.

Your analysis must include:

- **Project Structure Review:** Evaluate directory layout, module boundaries, naming consistency, and architectural clarity.  
- **Compiler Pipeline Audit:** Inspect parsing, AST construction, type checking, linear types, ownership model, memory semantics, IR generation, optimization passes, and codegen. Identify inconsistencies, missing invariants, or unclear semantics.  
- **Language Design Coherence:** Assess syntax, semantics, purity model, recursion strategy, tail‑call behavior, ADTs, pattern matching, and type system ergonomics.  
- **Error Handling & Diagnostics:** Identify gaps, unclear error paths, missing recovery mechanisms, weak diagnostics, or inconsistent messaging.  
- **Performance & Complexity Risks:** Highlight hotspots, unnecessary allocations, recursion depth risks, tail‑call issues, or structural inefficiencies.  
- **Safety & Correctness Review:** Identify undefined behavior risks, ownership leaks, linearity violations, type soundness issues, or compiler edge cases.  
- **Documentation Quality:** Evaluate README, examples, comments, and developer‑facing explanations. Identify missing sections, unclear concepts, or outdated information.  
- **DX & Maintainability:** Assess clarity, ergonomics, onboarding difficulty, code readability, and contributor experience.  
- **Testing Coverage:** Identify missing tests, weak coverage, untested invariants, or areas needing property‑based testing.  
- **Actionable Recommendations:** Provide a prioritized list of improvements, fixes, refactors, and architectural enhancements.

Output a **structured, multi‑section technical report** documenting your findings.  
Be thorough, precise, and objective.  
Do not include meta‑commentary about the prompt itself.
