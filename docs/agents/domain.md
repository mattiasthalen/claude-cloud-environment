# Domain Docs

How the engineering skills should **consume** a repo's domain documentation when
exploring it. These are reading rules only: they say what to look for where it
exists, and mandate no layout for a repo the session may not be allowed to
change.

## Before exploring, read these where they exist

- **`CONTEXT.md`** at the repo root.
- **`CONTEXT-MAP.md`** at the repo root, where the repo has one: it points at a
  `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`** — read the ADRs that touch the area you are about to work in.
  Where a context keeps its own decisions alongside its own `CONTEXT.md`, read
  those too.

If any of these are absent, **proceed silently**. Don't flag the absence, don't
suggest creating them upfront, and don't move a repo's files to match a layout
described here. The `/domain-modeling` skill (reached via `/grill-with-docs` and
`/improve-codebase-architecture`) creates them lazily, where they are wanted, when
terms or decisions actually get resolved.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal,
a hypothesis, a test name), use the term as defined in the `CONTEXT.md` you read.
Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either
you're inventing language the project doesn't use (reconsider) or there's a real
gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an ADR you read, surface it explicitly rather than
silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
