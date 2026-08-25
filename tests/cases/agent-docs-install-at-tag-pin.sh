#!/bin/bash
# The agent docs this repo ships land in every environment, whatever the
# argument list said. A run that requests no CLIs at all still installs all
# three, the verification block says so in one row, and the files are in the
# container afterwards.
#
# The row is also the pin assertion, and what makes it one is the harness shim:
# it serves the working tree at the pinned tag and refuses every other ref under
# the raw base, so a doc that landed could only have come from the tag-pinned
# URL. The contract is stated once, in docs/agents/testing.md under "The
# release-tag stand-in"; this case asserts on the script, not on the shim.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_output_contains "==> install agent docs"
assert_output_contains "✓ agent docs"

# The collected list is built from ~/.claude/docs/agents/ alone and skips empty
# files, so this also says each doc landed there with contents.
assert_agent_doc_installed issue-tracker.md
assert_agent_doc_installed triage-labels.md
assert_agent_doc_installed domain.md
