# Agent-first development starter

A lightweight, language-neutral repository template for a solo developer working with coding agents. It supplies shared instructions, product and architecture notes, a roadmap, short decision records, and reusable task prompts. It contains no application, dependencies, CI/CD, or prescribed toolchain.

## Context that survives a chat

- **Chat history** is useful for exploration, questions, and temporary coordination. It may be unavailable to the next agent.
- **Repository documentation and code** describe the current product, constraints, architecture, and important decisions. They are the persistent source of truth. Resolve contradictions explicitly rather than silently treating stale prose as correct.
- **Git history** records how the project changed and why. Small commits make changes easier to review and reverse; current guidance still belongs in current documentation.

Move agreed decisions and meaningful assumptions from chat into the relevant document. Keep documentation proportional to the project, and update it when reality changes.

## Start a new project

1. Create a repository from this template, or copy this directory into a new repository. Copying files alone does not initialize Git. If hosting on GitHub, you can designate the uploaded starter as a template repository.
2. Copy or rename `docs/PRODUCT.template.md` to `docs/PRODUCT.md`.
3. Fill in the product requirements, especially the problem, MVP, non-goals, constraints, and success criteria. Mark unknowns honestly.
4. Give your agent `.github/prompts/bootstrap.prompt.md` along with repository access. It creates working `docs/ARCHITECTURE.md` and `docs/ROADMAP.md` using the corresponding templates as needed.
5. Review the proposed architecture and significant decisions. Correct assumptions before deeper implementation.
6. Start M0/M1: establish a runnable foundation, then implement one small end-to-end use case.
7. Use the feature, bugfix, and investigate prompts for focused tasks. Use review before integrating meaningful changes and release before shipping.
8. Keep important decisions in repository documents; use short ADRs for consequential architectural choices.
9. Verify changes and commit frequently in small, coherent units.

Once customized, replace this README with project-specific setup, run, build, and test instructions. Record exact commands and prerequisites once known. The starter's guidance can be retained in a short section if useful.

## Keep it small

Not every project needs every file or section. A small experiment may need only `AGENTS.md`, a short product note, run instructions in its README, and a few roadmap checkboxes. Add architecture detail, ADRs, and tests when they help explain or protect real behavior. Use `Not applicable` where that is more informative than deleting a section. Keep reusable `.template.md` originals or remove them from a derived project once working documents exist.

These prompts are plain Markdown instructions. Paste their contents or ask your tool to read the file; automatic prompt discovery is not required. Agent tools vary in whether they automatically load `AGENTS.md`. If yours does not, explicitly ask it to read the root file before working. Use a tool-specific instruction file only if needed, pointing back to the shared rules rather than duplicating them.

## Files

| File | Purpose | Customize per project? |
| --- | --- | --- |
| `README.md` | Starter usage; replace with project setup and validation instructions | Yes |
| `AGENTS.md` | Short, shared agent behavior rules | Usually retain; add only necessary repository conventions |
| `.gitignore` | Minimal exclusions for local clutter and private environment files | Yes, after choosing a stack |
| `docs/PRODUCT.template.md` | Product definition scaffold | Fill a copy as `PRODUCT.md` |
| `docs/ARCHITECTURE.template.md` | Technical design scaffold | Fill a copy as `ARCHITECTURE.md` |
| `docs/ROADMAP.template.md` | Milestones and current priorities | Fill a copy as `ROADMAP.md` |
| `docs/decisions/README.md` | When and how to write an ADR | Usually retain |
| `docs/decisions/ADR-template.md` | Short decision scaffold | Copy for each decision |
| `.github/ISSUE_TEMPLATE/feature.md` | Focused feature request | Fill per issue; adapt if useful |
| `.github/ISSUE_TEMPLATE/bug.md` | Reproduction and expected behavior | Fill per issue; adapt if useful |
| `.github/prompts/bootstrap.prompt.md` | Create the minimal project foundation | Supply product requirements |
| `.github/prompts/feature.prompt.md` | Implement one bounded feature | Supply one feature |
| `.github/prompts/bugfix.prompt.md` | Diagnose and fix a bug | Supply reproduction evidence |
| `.github/prompts/investigate.prompt.md` | Research options without editing files | Supply one technical question |
| `.github/prompts/review.prompt.md` | Review a specified diff or change | Supply review scope |
| `.github/prompts/release.prompt.md` | Validate and prepare release notes | Supply intended release scope |
| `scripts/README.md` | Guidance for adding useful scripts later | Replace with actual usage when scripts exist |

## Git conventions

Use `main` by default. Work directly on it for small changes, or use short-lived feature branches when isolation helps. No complex branching strategy is required.

Make atomic commits: one coherent change with its relevant tests and documentation. Commit frequently at useful verified checkpoints, not after every file edit. Inspect the staged diff, avoid unrelated files, and record any incomplete validation. Agents should commit when requested or when an ongoing commit workflow has been agreed; otherwise suggest a commit message. Do not push, publish, or rewrite history without authorization.

Use a simple Conventional Commits style:

| Prefix | Use |
| --- | --- |
| `feat:` | New behavior |
| `fix:` | Bug correction |
| `refactor:` | Internal change without intended behavior change |
| `docs:` | Documentation |
| `test:` | Test additions or changes |
| `chore:` | Repository maintenance |

Examples: `feat: add export action`, `fix: handle empty input`, `docs: record storage decision`. No enforcement tooling is required.
