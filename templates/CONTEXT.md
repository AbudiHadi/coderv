# Project Vocabulary

> The shared language of this project — the words the code, docs, and conversations
> all use for the same thing. One term, one meaning, one code anchor.
>
> **Why this file exists:** agents (and new humans) dropped into a project use 20
> words where 1 will do, and name new code inconsistently, until someone hands them
> the project's own language. This file is that handoff. Say "the materialization
> cascade", not "the process where a lesson inside a section becomes real on disk".
>
> **Rules:**
> - Every term in the main table carries a **code anchor** — a `file:line` citation
>   or a grep-able identifier that proves the term lives in the code. `/lint` checks
>   anchors the same way it checks every other doc citation: anchor dead → term flagged.
> - Terms with no code counterpart (business/domain words the code never spells out)
>   go in **Domain-only terms** — `/lint` skips anchor-checking there by design and
>   only flags duplicates.
> - This is a glossary, nothing else. No specs, no implementation decisions (those
>   are ADRs in `docs/DECISIONS.md`), no scratch notes.
> - When a conversation uses a term that conflicts with this table, the conflict is
>   called out and resolved — then this file is updated in the same session.

## Terms

| Term | Meaning | Code anchor |
|---|---|---|
| <!-- e.g. Reservation --> | <!-- one line: what it means in THIS project --> | <!-- src/services/reservation.ts:12 or `CapReservation` --> |

## Domain-only terms

> Business language with no direct code counterpart. No anchors required here.

| Term | Meaning |
|---|---|
| <!-- e.g. Walk-in --> | <!-- a customer without a booking --> |
