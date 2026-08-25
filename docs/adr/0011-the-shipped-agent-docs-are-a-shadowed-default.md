# The shipped agent docs are a shadowed default

The engineering skills this repo installs read their contract from three
Markdown files a repository is expected to commit —
`docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md` and
`docs/agents/domain.md`. The plugin's own documentation is explicit that this is
the only arrangement it supports: it states that no user-level mode exists, and
that every repository carries its own `docs/agents/`.

`environment.sh` builds one anyway. It fetches those three files from its own
immutable tag into `~/.claude/docs/agents/`, on every provisioned box, alongside
the skills it already shipped there. The reason is the case the plugin's answer
does not cover: a session here works in whatever repository it is pointed at,
including repositories whose owners will not take a `docs/agents/` commit. In
those, a skill needing the tracker contract finds nothing, and either asks for
`/setup-matt-pocock-skills` to be run or reaches for a tracker that is not in
use.

What ships is a **shadowed default**, not an override. Resolution is per file:
for each of the three, a repo-local `docs/agents/<file>` wins where the
repository has one, and the shipped copy applies only where it does not. A
repository that has run setup is therefore unaffected, file by file. Per file
rather than per set, because the repository that committed only one of the three
would otherwise go wrong silently: under a set-level rule, a session would take
the other two for absent rather than for what applies.

Nothing in either copy states this rule — a file cannot say it is the one being
shadowed — so `~/.claude/CLAUDE.md` states it, in a bullet every session reads
first. `AGENTS.md`, `CONTEXT.md` and `README.md` carry it too, since the memory
file is an artifact this repo emits rather than a place it keeps its
conventions: the first two for a session working here, the third for a reader
deciding whether to provision a box at all.

## Considered options

**Inline the docs wholesale into `~/.claude/CLAUDE.md`** was rejected on prompt
size. The three docs are about 10 KB together; the memory file the script writes
is about 2 KB. Inlining them would take what every session carries before it has
done anything to about 12 KB — roughly six times the memory file — for a
contract most turns never consult. That runs against the trimming this repo does
deliberately elsewhere: the ten built-in tools
`0002-deny-list-trims-the-prompt.md` denies are denied to keep their schemas out
of the system prompt, and adding 10 KB back spends in one step what that
trimming is for. Files under `~/.claude/docs/agents/` cost nothing until a skill
opens one, the shape the skills were written for.

What the memory file carries instead is the resolution rule plus two facts in
summary — the tracker is GitHub, and the five triage labels are equal to their
role names — so a session opens a doc for the operations, not to learn where it
is. Anything larger belongs in the shipped files.

**Commit `docs/agents/` into each target repository**, the plugin's own answer,
was rejected as the general rule: the repositories that most need the contract
are exactly the ones that cannot take the commit. It stays preferred where it is
possible — a repository that commits the files owns its own contract, which is
what the per-file rule is for.

**Let the shipped copy win** was rejected outright: provisioning this
environment would silently change how skills behave in repositories that had
deliberately configured them, with the committed file still sitting in the tree
looking authoritative.

## Consequences

The shipped copies are pinned to the tag the box was provisioned from, like the
skills and every tool version, so a box on an older tag carries the contract
that tag shipped. That is the intended trade — a change reaches an environment
only when someone edits its box — but the shipped set is a floor, never a
guarantee of currency.

The shipped docs are this repo's own `docs/agents/` files, so they are written
for a session working anywhere and name no repository; the line naming this
repository's tracker lives in `AGENTS.md`, which is not shipped. Nor is
`docs/agents/testing.md` — it describes this repo's container suite and would be
false everywhere else.

The fetch is not fatal to the steps after it: a failed docs fetch is collected
rather than aborting the run, so the CLIs the box was provisioned for still
install. The run then ends with one recap entry naming the step and exits 1, as
any failed step does, and a session on such a box has only whatever the
repository carries — which is why the failure is named rather than swallowed.
