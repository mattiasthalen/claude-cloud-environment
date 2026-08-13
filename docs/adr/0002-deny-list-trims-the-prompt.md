# The deny list trims the system prompt, and is not a capability boundary

`environment.sh` writes a `permissions.deny` array into `~/.claude/settings.json`. Every entry is held to one criterion: make the system prompt smaller, minus whatever the session needs to keep supporting its user. Nothing in that array is there to make an action impossible, and reading it as a security boundary will mislead you.

This decision governs the deny array only. The same block also writes a `permissions.allow` array, added later and answering to the opposite criterion — see `0004-the-allow-list-buys-determinism-not-reach.md`.

Two facts about the mechanism decide most of the list, and neither is obvious from the settings documentation:

- Denying a **built-in tool** keeps its schema out of the system prompt. This is where the saving comes from.
- Denying a **skill** does not. A denied skill still appears in the session's skill listing, description included, and is refused only when invoked.

So the seven denied `caveman:*` skills buy exactly one thing — `/code-review` is the only review path on offer, the enforced half of what `~/.claude/CLAUDE.md` asks for — and buy no prompt savings at all. The ten denied built-ins buy the savings.

A third fact bounds the list's reach: several denied built-ins have MCP equivalents that are not denied. The Claude Code Remote server exposes `create_trigger`, `list_triggers`, `delete_trigger` and `send_later`, covering what `CronCreate`, `CronList`, `CronDelete` and `ScheduleWakeup` cover, and a tool name containing `_` is exempt even from the startup typo check these rules receive. A remote session is told by its own harness to schedule PR check-ins, so this is left as is on purpose: those four entries mean "out of the prompt", not "cannot happen".

## Considered options

Denying `AskUserQuestion` and `SendMessage` too, which the list did until this decision. Reverted on the second half of the criterion. Under `permissions.defaultMode = "auto"` — which this script also sets — `AskUserQuestion` is the session's only route to its user, and the remote harness names it as the path for an ambiguous review comment; denying it removed the ability to ask without removing the situations that warrant asking. `SendMessage` is how an existing subagent is resumed, so without it a session can spawn agents but never continue one, and every follow-up question pays full context re-discovery — more prompt than the two schemas ever cost.

> **Superseded for `AskUserQuestion` only, by `0007-the-question-box-goes-prose-replaces-it.md`.** It is denied again, on a ground this ADR does not weigh — the question box is a UI the user will not work in — and paired with a `CLAUDE.md` bullet that routes the same questions into prose, which is what answers the objection above. That ADR also corrects "the session's only route to its user": a turn ending with a question in prose reaches the user by the same route every reply does. Everything in this paragraph about `SendMessage` stands.

Dropping the caveman plugin and vendoring only its session hook, which would take its eight skill listings out of the prompt for real, since the response style comes from the hook rather than from any skill. Rejected: it trades a supported `claude plugin install` for a vendored file this repo then owns and has to track upstream. `skills/swarm/SKILL.md` is already that arrangement, and its own comment treats vendoring as debt to be deleted the moment upstream ships a package. Taking on a second instance of that debt to recover eight skill descriptions is a poor rate. If prompt size later outweighs the maintenance, this option is still available.

Denying MCP tools as well, which is the largest remaining lever — a session here can carry the GitHub, Claude Code Remote, Google Drive and Gmail servers. Left unexamined. Their tools arrive deferred, as names with schemas fetched on demand, so they cost less than their count suggests, and they are environment-level configuration rather than `settings.json` deny rules. Auditing them is a separate pass.

## Consequences

`permissions.deny` cannot be read as a list of things this environment prevents, and the entries do not all earn the same thing. That is why `environment.sh` keeps the two halves apart with a comment on each, and why `tests/cases/settings-json-shape.sh` asserts `SendMessage`'s absence as explicitly as it asserts the presence of the rest — a reverted entry is precisely what a later tidy-up of the list would restore without noticing the cost. The same file asserted `AskUserQuestion`'s absence for the same reason until `0007` put it back.

Every entry was checked against the tool reference when this was written; `DesignSync` was removed because no such tool exists, and a deny rule naming no known tool produces a startup warning instead of an effect. Any entry added later needs the same check, because a misspelled name reads to every future reader as a capability that is blocked when it is not.
