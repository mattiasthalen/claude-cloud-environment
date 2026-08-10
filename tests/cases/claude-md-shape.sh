#!/bin/bash
# After a run, ~/.claude/CLAUDE.md carries every standing rule a provisioned
# session depends on: the caveman mode it answers in, and the note that
# `/code-review` fans out to a subagent per axis by design. The file's contents
# are the contract, the same way settings.json's shape is.
#
# The review line is asserted because it exists to survive a session that would
# otherwise route around the skill — a line that silently stopped being written
# would take that with it, with nothing else in the suite noticing.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_claude_md_contains 'caveman `full` mode'
assert_claude_md_contains '`/code-review` spawns one subagent per axis'
