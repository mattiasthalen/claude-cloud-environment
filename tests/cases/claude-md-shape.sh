#!/bin/bash
# After a run, ~/.claude/CLAUDE.md carries every standing rule a provisioned
# session depends on: the caveman mode it answers in, the standing request for
# subagents, the note that `/code-review` fans out to a subagent per axis by
# design, the instruction to end a turn with an unsettled question in prose, and
# which copy of each agent doc a session is acting on. The file's contents are
# the contract, the same way settings.json's shape is.
#
# The review line is asserted because it exists to survive a session that would
# otherwise route around the skill — a line that silently stopped being written
# would take that with it, with nothing else in the suite noticing.
#
# The subagent rule is asserted in two halves, and the second half is the one
# worth explaining. "Subagents are wanted here" without "the permission rules
# are the boundary" tells a session to fight the `cavecrew-*` denies in
# settings.json rather than accept them, and the boundary clause is exactly what
# a future editor trimming the bullet for brevity would drop first. Asserting it
# separately is what makes that trim fail here instead of in a session.
#
# The voice line is asserted in two halves for the same reason the subagent rule
# is. The precedence clause is what makes the voice a layer rather than a rival
# ruleset, and it is the first thing an editor shortening a long bullet would
# drop — leaving a session with two style rules and no way to tell which yields.
#
# The blocking-ask line is asserted for a sharper reason: it is the half of a
# pair whose other half lives in settings.json's deny array. If this line goes
# missing while `AskUserQuestion` stays denied, sessions lose the tool and the
# instruction to ask without it at the same time, and start guessing silently.
# See docs/adr/0007-the-question-box-goes-prose-replaces-it.md.
#
# The agent-docs line is asserted in two halves, and they are asserted together
# because they answer the same question from opposite ends. The first half is
# the resolution rule — repo-local `docs/agents/<file>` shadows the shipped
# `~/.claude/docs/agents/<file>`, per file — which is what stops a session that
# found one copy from assuming it found the only one. The second half is the
# summary a session holds when it opens neither copy: that the tracker is
# GitHub, and the five canonical triage labels, each equal to its role name. A
# bullet that kept the rule and lost the summary would send every session to a
# file for two facts it should already have; one that kept the summary and lost
# the rule would let a session act on the shipped defaults in a repo that
# overrode them. Neither half is worth much without the other, so a trim of
# either fails here.
#
# The third clause of the same bullet is the absence branch, and it is asserted
# separately from the other two. The docs fetch is collected rather than fatal,
# so a box can finish provisioning with no shipped docs at all; a bullet that
# named only the two present-copy branches would tell such a session that the
# shipped copy applies, and leave it acting on the summary as though that were
# the contract. Pinning "say so" and the `/setup-matt-pocock-skills` nudge is
# what makes a trim of the branch fail here rather than on a box whose fetch
# failed. See story 16 of #86.
#
# The label strings are pinned here verbatim, so this file is a site a rename
# has to visit. The source table in `docs/agents/triage-labels.md` ships into
# repositories that have no such file, so it cannot list this site; `AGENTS.md`
# does, under "Renaming something the shipped set names".
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_claude_md_contains 'caveman `full` mode'
assert_claude_md_contains 'Voice in chat is Rocky'
assert_claude_md_contains 'caveman wins'
assert_claude_md_contains 'this line is that request'
assert_claude_md_contains 'the permission rules are the boundary'
assert_claude_md_contains '`/code-review` spawns one subagent per axis'
assert_claude_md_contains 'end the turn with the question in prose'
assert_claude_md_contains 'a repo-local `docs/agents/<file>` wins if the repository has one'
assert_claude_md_contains 'otherwise the shipped copy at `~/.claude/docs/agents/<file>` applies'
assert_claude_md_contains 'Shadowing is per file'
assert_claude_md_contains 'Where neither copy exists'
assert_claude_md_contains 'say so rather than acting on the summary alone'
assert_claude_md_contains 'run `/setup-matt-pocock-skills`'
assert_claude_md_contains 'the tracker is GitHub'
assert_claude_md_contains '`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human` and `wontfix`'
