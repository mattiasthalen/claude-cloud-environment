#!/bin/bash
# The release-tag stand-in covers the whole repository, not only `skills/`. A
# fetch of any other tag-pinned path — here an agent doc, tomorrow whatever the
# next shipped artifact is — gets the working tree's own copy back, with no
# further harness change. That is what lets a later step ship a file from
# outside `skills/` and still be tested at the pin.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
# Exactly the URL shape environment.sh builds for a shipped artifact: the raw
# base, the release tag, then a path in the repository.
mkdir -p ~/.claude/docs/agents
curl -fsSL "$(cat /tmp/harness-tag-url)/docs/agents/issue-tracker.md" \
  -o ~/.claude/docs/agents/issue-tracker.md
PRE

harness_run

assert_status 0
assert_agent_doc_installed issue-tracker.md
