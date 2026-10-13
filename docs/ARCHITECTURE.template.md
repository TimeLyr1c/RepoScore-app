# Architecture

Copy or rename this file to `ARCHITECTURE.md`. Describe the current design and label proposed work clearly. Keep overview, stack, structure, and verification guidance useful; omit other sections that do not apply, or mark them `Not applicable` with a brief reason. Do not invent networking, persistence, or components to fill headings. Link consequential decisions to ADRs.

## Overview
Explain the system's responsibilities, boundaries, and simplest overall design in a short paragraph.

## Technology stack
List selected languages, runtimes, frameworks, and relevant versions. Explain choices briefly and mark unresolved choices.

## Project structure
Show the meaningful directories and their responsibilities. Update this after scaffolding; avoid listing every file.

## Major components
Describe the main components and their interfaces. Include only components the project needs.

## Data flow
Trace one key input through processing to output. Plain text is enough; use a small diagram only if it helps.

## State management
Explain where state lives, who owns it, and how updates propagate. Omit if no meaningful shared state exists.

## Persistence
Describe stored data, storage choice, and any migration or recovery needs. Omit for a stateless project.

## Networking
Describe network boundaries, failure handling, and offline expectations. Omit if no network access is needed.

## External dependencies
List direct dependencies or services and why each is needed. Note meaningful maintenance or portability costs. Write `None` if there are none.

## Testing strategy
Explain what automated tests should protect, what needs manual verification, and where exact build/run/test commands are documented. Cover the core use case and relevant failure paths; do not mandate every test type.

## Performance-sensitive areas
Identify actual latency, memory, throughput, or resource constraints and how to measure them. Omit until a real sensitivity is known.

## Security/privacy considerations
Describe sensitive data, trust boundaries, permissions, and relevant controls. Include only applicable risks; never write credentials into this document.

## Platform constraints
Record relevant platform lifecycle, compatibility, distribution, device, or runtime limits. Omit if the stack section covers everything needed.

## Known tradeoffs
Describe accepted limitations and why they are acceptable now. Link ADRs instead of duplicating their reasoning.

## Open technical questions
List unknowns, assumptions to verify, and decisions that block progress. Distinguish current facts from proposals.
