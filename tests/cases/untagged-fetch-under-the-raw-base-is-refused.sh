#!/bin/bash
# The stand-in refuses, rather than delegates. A fetch under this repo's raw
# base at any ref other than the release tag exits non-zero and lands no file,
# so it cannot quietly succeed against a branch on GitHub. That refusal is what
# makes a passing fetch case evidence of the tag pin: the only ref that serves
# anything in here is the pinned one.
#
# The real curl is stubbed to serve whatever it is asked for, so a delegated
# fetch would land the file and fail this case rather than depending on what
# GitHub happens to answer.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
cat > /tmp/harness-stub-curl <<'STUB'
#!/bin/bash
prev=""
for arg in "$@"; do
  case "${prev}" in
    -o | --output) printf 'served by the real curl\n' > "${arg}" ;;
  esac
  prev="${arg}"
done
STUB
chmod +x /tmp/harness-stub-curl
printf '%s\n' /tmp/harness-stub-curl > /tmp/harness-real-curl

mkdir -p ~/.claude/docs/agents
if curl -fsSL "$(cat /tmp/harness-raw-base)/refs/heads/main/docs/agents/issue-tracker.md" \
  -o ~/.claude/docs/agents/issue-tracker.md; then
  printf 'the fetch succeeded\n' > ~/.claude/docs/agents/branch-ref-served.md
else
  printf 'the fetch was refused\n' > ~/.claude/docs/agents/branch-ref-refused.md
fi
PRE

harness_run

# Non-zero exit, and nothing written: not a delegated fetch, not a partial file.
assert_agent_doc_installed branch-ref-refused.md
assert_agent_doc_absent branch-ref-served.md
assert_agent_doc_absent issue-tracker.md
