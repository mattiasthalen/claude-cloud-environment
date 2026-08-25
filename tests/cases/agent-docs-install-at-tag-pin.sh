#!/bin/bash
# The agent docs this repo ships land in every environment, whatever the
# argument list said. A run that requests no CLIs at all still installs all
# three, the verification block says so in one row, and the files are in the
# container afterwards.
#
# The row is also the pin assertion: the harness serves files for exactly the
# prefix built from `refs/tags/v${SCRIPT_VERSION}/`, and refuses any other URL
# under the raw base — so a doc that landed could only have come from the
# tag-pinned URL.
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
