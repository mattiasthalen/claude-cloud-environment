#!/bin/bash
# After a run, ~/.claude/CLAUDE.md carries every standing rule a provisioned
# session depends on: the caveman mode it answers in, the standing request for
# subagents, the note that `/code-review` fans out to a subagent per axis by
# design, and the instruction to end a turn with an unsettled question in prose.
# The file's contents are the
# contract, the same way settings.json's shape is.
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
