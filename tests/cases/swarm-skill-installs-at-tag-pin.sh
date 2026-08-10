#!/bin/bash
# The skill this repo ships lands in every environment, whatever the argument
# list said. A run that requests no CLIs at all still installs it, the
# verification block says so in one row, and the file is in the container
# afterwards.
#
# The row is also the pin assertion: the harness serves a skill file for exactly
# one URL, the one built from `refs/tags/v${SCRIPT_VERSION}/`, and refuses any
# other — so a skill that landed could only have come from the tag-pinned URL.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_output_contains "==> install swarm skill"
assert_output_contains "✓ swarm skill"
assert_skill_installed swarm

printf '%s\n' "${HARNESS_SKILLS}" | grep -qx "swarm /root/.claude/skills/swarm/SKILL.md" ||
  harness_fail "expected the skill at ~/.claude/skills/swarm/SKILL.md, found: ${HARNESS_SKILLS:-<none>}"
