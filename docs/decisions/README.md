# Architecture Decision Records

An Architecture Decision Record (ADR) is a short note explaining a consequential technical choice, its context, and its tradeoffs. It lets a future developer or agent understand why the project works this way without reconstructing a chat.

## When to create one

Use an ADR for choices with lasting consequences or meaningful alternatives: a framework, storage model, major system boundary, external service, or significant security/privacy approach. Also record a deliberate reversal of a previous decision. A small project may need none.

## When not to create one

Skip ADRs for routine bug fixes, naming preferences, minor implementation details, or choices easily explained by a code comment. Product requirements belong in `PRODUCT.md`; task progress belongs in `ROADMAP.md`. Avoid duplicating those documents.

## Naming and lifecycle

Copy `ADR-template.md` to the next unused four-digit number and a short lowercase hyphenated title:

- `0001-use-swiftui.md`
- `0002-local-first-storage.md`

These names are examples, not prescribed technology choices. Use status `Proposed`, `Accepted`, `Rejected`, or `Superseded`. A proposal is not yet an accepted constraint. Record the date alongside status. For accepted decisions, preserve the original rationale; when a choice changes, add a new ADR, mark the previous one superseded, and link both records. Update `ARCHITECTURE.md` to describe the current design.

Aim for a few paragraphs or bullets, usually under one page. Explain only enough to understand the choice. Link relevant evidence or validation when helpful; no approval committee or extra index is required.
