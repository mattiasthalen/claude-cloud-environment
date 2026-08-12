# The allow list buys determinism, not reach

`environment.sh` writes a `permissions.allow` array alongside the deny array, holding the two Claude Code Remote tools that attach a repository to a running session: `add_repo` and `register_repo_root`. Its criterion is the opposite of the deny list's. `0002-deny-list-trims-the-prompt.md` holds every deny entry to "make the system prompt smaller" and states that nothing in that array is there to make an action impossible. Allow entries make nothing possible either — they make an already-possible action *predictable*.

The distinction matters because of what the entries replace. Under `permissions.defaultMode = "auto"`, which this script also sets, any call matching no rule is put to the auto-mode classifier, and the classifier's verdict on repo attachment is not a function of the call. The same `add_repo` — same owner, same repository, same access level — was denied twice and then allowed on a third attempt, the only change being that the user had said "add the repo" in chat in the meantime. A separate unprompted call against a public repository was allowed where the denied ones were private; that is one observation each and not enough to call a rule, but it points the same way. The verdict is a per-call judgement that reads conversational context, and an unattended session — trigger-fired, scheduled, CI-driven — has no such context to offer. It stalls and waits for a human who may not be watching.

An allow rule is the only remedy that removes the variance rather than improving the odds. It grants no reach the workspace did not already have: `add_repo` performs its own entitlement check server-side and returns a structured error for repositories the workspace is not authorised for, so the classifier was a second gate standing over an existing one, and the one being removed is the non-deterministic one.

`register_repo_root` is in the array because attachment is two calls. `add_repo` returns a clone command, and the clone's `CLAUDE.md`, skills and plugins do not load until `register_repo_root` reports the path back. Granting only the first moves the same wall one step later, to a point where it presents as a cloned-but-inert repository rather than as a permission denial — a worse failure than the one being fixed, because it is harder to read.

## Considered options

**Making the grant opt-in**, arriving only when named on the invocation line the way `gcloud` or `snow` do, was rejected. It would keep default provisioning tight, which is this script's habit elsewhere, but it costs argument parsing and test cases for both states to reach an outcome whose blast radius is already bounded by the server-side entitlement check. The capability is not one an environment benefits from lacking.

**Carrying both spellings of the server segment** — `Claude_Code_Remote` and `claude-code-remote` — as insurance was considered and rejected in favour of the one spelling that is correct today. The tool name is built as `mcp__` + server + `__` + tool, with the server's display name sanitised by mapping every character outside `[a-zA-Z0-9_-]` to `_`; the backend registers "Claude Code Remote", so spaces become underscores and the capitals survive. The CLI separately carries the lower-case hyphenated form as an internal constant, which is where the second spelling came from. Two entries would have been robust to a rename at the cost of two permanently inert lines that read as noise to anyone tidying the list.

**A server-level rule** — a bare `mcp__Claude_Code_Remote` entry, which the matcher does accept as a wildcard over every tool the server exposes — was rejected as far past the need. It would also grant `create_session`, `create_trigger` and `send_message`.

**Re-enabling `AskUserQuestion` instead**, which the originating issue suggested as an alternative, was moot by the time this was written: it had already left the deny list for its own reasons, recorded in `0002`. It would not have fixed this in any case. A prompt in an unattended session stalls exactly as a written explanation does, and unattended stalls are the whole cost being paid.

## Consequences

`permissions` in the generated settings can no longer be read as a single list with a single purpose. The two halves answer to opposite criteria, and `0002`'s framing — nothing here makes an action impossible — describes the deny half only.

The grant applies to every environment this script provisions, not only to the cross-repo case that prompted it. That is deliberate, and it means any session in any such environment can pull any repository the workspace is entitled to into its container without asking. The entitlement check is what bounds this; the classifier no longer is.

Both names were checked against a live session's tool list, which is the check `0002` asks of every entry added to this block. An allow rule earns that check twice over: a deny rule naming no known tool at least produces a startup warning, whereas an allow rule that matches nothing loads, parses and matches nothing, silently. If the backend ever renames the server, the symptom will be the original classifier denials returning, and the fix is to re-derive the names from a live tool list rather than to trust the spelling recorded here.

`verify_settings` reads back both entries rather than one, and `tests/cases/settings-json-shape.sh` asserts both by exact literal, capitals included. Neither proves the rule is honoured — no test here starts a Claude session — but both catch the case where the plugin commands' rewrite of `settings.json` drops them.
