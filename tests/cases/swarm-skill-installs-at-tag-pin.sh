#!/bin/bash
# The skill this repo ships lands in every environment, whatever the argument
# list said. A run that requests no CLIs at all still installs it, the
# verification block says so in one row, and the file is in the container
# afterwards.
#
# The row is also the pin assertion, and what makes it one is the harness shim:
# it serves the working tree at the pinned tag and refuses every other ref under
# the raw base, so a skill that landed could only have come from the tag-pinned
# URL. The contract is stated once, in docs/agents/testing.md under "The
# release-tag stand-in"; restating it here is how the two tag-pin cases came to
# describe the same shim in words that disagreed.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_output_contains "==> install swarm skill"
assert_output_contains "✓ swarm skill"

# The collected list is built from ~/.claude/skills/*/SKILL.md alone, so this
# also says the skill landed in the user-level skills directory.
assert_skill_installed swarm
