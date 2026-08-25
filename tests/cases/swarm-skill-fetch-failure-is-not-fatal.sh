#!/bin/bash
# A skill fetch that fails costs one absent slash command, not the environment.
# The failure is collected like any other step — named in the one recap, exit 1
# — but the run carries on past it: the settings are still written and the
# verification block still runs.
#
# It is also reported once. The verification row says the skill is absent, which
# is what that block is for, without adding a second entry to the recap for the
# same breakage.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# Fail the skill fetch and nothing else: the other tag-pinned artifacts still
# land, which is what makes the recap count below a statement about one
# breakage. The scaffolding lives in tests/lib.sh (see docs/agents/testing.md).
harness_pre_curl_fails '*SKILL.md' 22 \
  'curl: (22) The requested URL returned error: 404'

harness_run

assert_status 1
assert_output_contains "!!! step failed: install swarm skill"
assert_output_contains "  - install swarm skill"
assert_output_contains "✗ swarm skill"
assert_skill_absent swarm

# The rest of the run happened anyway.
assert_output_contains "✓ settings.json"

# One entry for one breakage: the recap carries the failed fetch and not a
# second entry for the verification row it caused.
assert_output_contains "1 step(s) failed"
