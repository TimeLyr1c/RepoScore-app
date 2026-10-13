# Agent instructions

- Inspect the repository and working tree before changing files. Read the README and relevant product, architecture, roadmap, and decision documents when present; understand the existing implementation first.
- Repository documentation and code are the persistent source of truth, not chat history. Surface contradictions and record important decisions and assumptions in the repository.
- For non-trivial work, state a short implementation plan before modifying code: scope, affected components, approach, and verification. Persist it in an existing issue or relevant roadmap entry when useful for handoff; no separate plan file is required.
- Prefer small, focused changes. Implement only the requested scope; preserve unrelated work and existing conventions. Do not rewrite working code without a concrete reason or refactor unrelated code.
- Prefer simple solutions over speculative abstractions. Avoid over-engineering. Justify any new dependency by its need, cost, and simpler alternatives.
- Ask for clarification only when necessary to avoid materially wrong or unsafe work. Otherwise make reasonable assumptions and document meaningful ones.
- Add or update tests where they protect relevant behavior. Use appropriate build, run, and test checks; do not add tooling solely for process.
- After implementation, inspect the final diff, build where applicable, and run relevant tests or other validation. Report exact checks, results, warnings/errors, skipped checks and reasons. Never claim an unperformed check passed.
- Update documentation when behavior, setup, or architecture changes. Record consequential architectural choices as short ADRs in `docs/decisions/`.
- Summarize changes, verification, and remaining limitations. Favor frequent atomic commits under the agreed Git workflow; inspect staged changes and exclude unrelated files. Do not push, publish, or rewrite history without authorization.
