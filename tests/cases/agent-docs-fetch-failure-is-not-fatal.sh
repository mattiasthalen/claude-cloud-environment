#!/bin/bash
# A docs fetch that fails costs the docs, not the environment. The failure is
# collected like any other step — named in the one recap, exit 1 — but the run
# carries on past it: the settings are still written and the verification block
# still runs.
#
# It is also reported once. The verification row says the docs are absent, which
# is what that block is for, without adding a second entry to the recap for the
# same breakage. And a transfer that failed part-way leaves nothing behind: a
# truncated file would verify as present, so absence has to be honest.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# Fail the docs fetch and nothing else: the swarm skill still lands from its
# tag-pinned URL, which is what makes the recap count below a statement about
# one breakage. The partial text is the truncated file curl itself would leave
# behind, so the case tests the cleanup rather than curl's absence. The
# scaffolding lives in tests/lib.sh (see docs/agents/testing.md).
harness_pre_curl_fails '*/docs/agents/*' 18 \
  'curl: (18) transfer closed with outstanding read data remaining' \
  'half a doc'

harness_run

assert_status 1
assert_output_contains "!!! step failed: install agent docs"
assert_output_contains "  - install agent docs"
assert_output_contains "✗ agent docs"

# Nothing partial left behind, for any of the three.
assert_agent_doc_absent issue-tracker.md
assert_agent_doc_absent triage-labels.md
assert_agent_doc_absent domain.md

# The rest of the run happened anyway.
assert_output_contains "✓ settings.json"

# One entry for one breakage: the recap carries the failed fetch and not a
# second entry for the verification row it caused.
assert_output_contains "1 step(s) failed"
