#!/bin/bash
# After a run, ~/.claude/CLAUDE.md carries every standing rule a provisioned
# session depends on: the caveman mode it answers in, the note that
# `/code-review` fans out to a subagent per axis by design, and the instruction
# to end a turn with an unsettled question in prose. The file's contents are the
# contract, the same way settings.json's shape is.
#
# The review line is asserted because it exists to survive a session that would
# otherwise route around the skill — a line that silently stopped being written
# would take that with it, with nothing else in the suite noticing.
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
assert_claude_md_contains '`/code-review` spawns one subagent per axis'
assert_claude_md_contains 'end the turn with the question in prose'
