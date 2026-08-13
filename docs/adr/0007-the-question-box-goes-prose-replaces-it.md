# The question box goes, and prose replaces it

`environment.sh` denies `AskUserQuestion` again, and adds a `~/.claude/CLAUDE.md` bullet telling a session to end its turn with the question in prose when a decision is genuinely unsettled. This supersedes the `AskUserQuestion` paragraph of `0002-deny-list-trims-the-prompt.md` — and only that paragraph. The deny list's criterion, and every other entry held to it, are unchanged.

The reason is not the one `0002` weighs. It is not prompt size, and it is not a capability this environment should lack: the question box the tool renders is a UI the user of these environments will not work in. That is a presentation complaint, and it is worth recording because presentation is the one axis neither of this repo's two permission ADRs considers — `0002` trims the prompt, `0004` buys determinism, and a reader holding this entry up against either criterion will conclude it does not belong.

This entry has now flipped twice. It was denied, reverted in `0002`, and is denied again here. The flip-flop is the most useful thing a future reader can know about it, which is why this is a new ADR rather than an edit to `0002`: the earlier reasoning was not wrong when written, and a reader who sees only the current state will re-derive it and revert again.

## What answers the objection in 0002

`0002` reverted this entry because denying the tool "removed the ability to ask without removing the situations that warrant asking". That objection is real and is not dismissed here — it is answered by the CLAUDE.md bullet, which is why the two are described together in `environment.sh` and asserted together in `tests/`. Deny alone is not the decision recorded here, and shipping it alone reproduces the exact failure that caused the first revert.

`0002` also states that `AskUserQuestion` is "the session's only way to reach its user at all" under `permissions.defaultMode = "auto"`. That is overstated, and the overstatement is what made the entry look impossible to remove. A turn that ends with a question in prose reaches the user by the same route every other reply does; the user reads it and answers, and the session resumes. What the tool uniquely provides is a *structured* box and a notification, not reachability.

The bullet inherits the caveat the memory file's other rules carry, spelled out at its own comment in `environment.sh`: a memory file does not outrank a system prompt. It raises the odds that an unsettled decision comes back as a question rather than as a guess. It does not settle the matter, and a session that guesses anyway is not a bug in this decision — it is its known cost, accepted against a UI the user will not use.

## Considered options

**Keeping the tool and instructing sessions to prefer prose** was the recommendation put to the user and was rejected by them. It would have kept the escape hatch for a session that genuinely must block, at the cost of the box still appearing whenever a session reached for the tool despite the instruction — which, given the caveat above, it sometimes would. The user's position is that the box should not be reachable at all; the instruction alone leaves it reachable.

**Un-denying `PushNotification`** so a prose question pings a phone rather than sitting in a transcript was considered and rejected. The complaint being answered here is about being interrupted by a UI; a push is a different interruption, not a smaller one. It is cheap to revisit if prose questions start going unnoticed.

**Denying `SendMessage` alongside it**, as the original pre-`0002` list did, was rejected. Its revert in `0002` stands on its own reasoning — subagent resumption — which nothing here touches. `tests/cases/settings-json-shape.sh` asserts the two in opposite directions for this reason.

**Covering local machines too.** The user asked for this everywhere. `environment.sh` writes `~/.claude/settings.json` inside provisioned containers only, and a README snippet for a local settings file was offered and rejected: this repo provisions cloud environments and does not configure anyone's laptop. "Everywhere" therefore means every environment this repo provisions, and local Claude Code installs are out of scope by the repo's own boundary.

## Consequences

The deny array now holds an entry that fails `0002`'s criterion, so `0002` can no longer be read as governing the whole array. `environment.sh` carries a comment at the entry saying so, and `0002` points forward to here.

The deny and the CLAUDE.md bullet are a pair with no mechanism binding them together at runtime — nothing fails if one is removed. The binding is in the test suite: `settings-json-shape.sh` asserts the deny, `claude-md-shape.sh` asserts the bullet, and both comments name the other half. Anyone deleting one needs to delete the other deliberately.
