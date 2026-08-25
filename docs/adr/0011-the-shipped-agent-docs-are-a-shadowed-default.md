# The shipped agent docs are a shadowed default

The engineering skills this repo installs read their contract from three
Markdown files a repository is expected to commit —
`docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md` and
`docs/agents/domain.md`. The plugin's own documentation is explicit that this is
the only arrangement it supports: asked whether the config can live in
`~/.claude` instead of being committed to every repository, it answers "Not
today. There is an open request for exactly this from someone running the skills
across many repos, and no user-level mode exists. Every repo carries its own
`docs/agents/`."

`environment.sh` builds one anyway. It fetches those three files from its own
immutable tag into `~/.claude/docs/agents/`, on every provisioned box, alongside
the skills it already shipped there. The reason is the case the plugin's answer
does not cover: a session here works in whatever repository it is pointed at,
including repositories whose owners will not take a `docs/agents/` commit — a
client's, a repository under someone else's review policy, one where the change
is simply not worth arguing for. In those, a skill that needs the tracker
contract finds nothing, and either asks for `/setup-matt-pocock-skills` to be
run or falls back to a tracker that is not the one in use. Shipping the docs
means the contract is present in every repository the box touches, whether or
not that repository could carry it.

What ships is a **shadowed default**, not an override. Resolution is per file:
for each of the three, a repo-local `docs/agents/<file>` wins where the
repository has one, and the shipped copy applies only where it does not. A
repository that has run setup is therefore unaffected, file by file — nothing
that already works starts behaving differently because a box was provisioned
from a newer tag. Per file rather than per set, because the repository that
committed only one of the three is the case that would otherwise go wrong
silently: with a set-level rule, a session would take the shipped copies of the
other two for absent rather than for what applies.

Nothing in either copy states this rule — a file cannot say it is the one being
shadowed — so `~/.claude/CLAUDE.md` states it, in a bullet every session reads
before it opens anything. `AGENTS.md` and `CONTEXT.md` carry it as well, because
this repo records its conventions there and the memory file is an artifact it
emits rather than a place it keeps them.

## Considered options

**Inline the docs wholesale into `~/.claude/CLAUDE.md`** was rejected on prompt
size. The three docs are about 10 KB together; the memory file the script writes
is about 2 KB. Inlining them would multiply what every session in the
environment carries in its prompt, before it has done anything, by roughly five
— for a contract most turns never consult. That runs directly against the
trimming this repo does deliberately elsewhere:
`0002-deny-list-trims-the-prompt.md` holds every deny entry to the criterion of
making the prompt smaller, and inlining would spend more than that whole list
recovers. Files under `~/.claude/docs/agents/` cost nothing until a skill opens
one, which is the shape the skills were written for.

What the memory file carries instead is the resolution rule plus two facts in
summary — the tracker is GitHub, and the five triage labels are equal to their
role names. Those are the two the skills reach for constantly and cheaply, so a
session that already has them opens a doc when it needs the operations, not to
learn where it is. That is a deliberate line, not the beginning of an inlining:
anything larger belongs in the shipped files.

**Commit `docs/agents/` into each target repository**, the plugin's own answer,
was rejected as the general rule for the reason above — the repositories that
most need the contract are exactly the ones that cannot take the commit. It
remains available and remains preferred where it is possible: a repository that
commits the files shadows the shipped ones and owns its own contract, which is
what the per-file rule is for.

**Let the shipped copy win** was rejected outright. It would make provisioning
this environment change the behaviour of skills in repositories that had
deliberately configured them, silently, with the repository's committed file
still sitting in the tree looking authoritative.

## Consequences

The shipped copies are pinned to the tag the box was provisioned from, like the
skills and every tool version, so a box sitting on an older tag carries the
contract that tag shipped. That is the intended trade — a change reaches an
environment only when someone edits its box — but it means the shipped set is a
floor a repository can raise and never a guarantee of currency.

The shipped docs are this repo's own `docs/agents/` files, so they are written
for a session working anywhere and name no repository. `AGENTS.md` is where the
one line naming this repository's tracker lives, because `AGENTS.md` is not
shipped. `docs/agents/testing.md` is not part of the shipped set: it describes
this repo's container suite and would be false everywhere else.

The fetch is not fatal to a run. A box whose docs fetch failed reports it in the
recap and otherwise provisions normally, so a session there falls back to
whatever the repository carries — which is precisely the situation this decision
exists to improve, and is why the failure is reported rather than swallowed.
