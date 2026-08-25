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

harness_pre <<'PRE'
# Shadow the harness curl, which would otherwise serve the docs. The shim is
# kept aside first and everything that is not a docs fetch is handed straight
# back to it, so this case fails the docs fetch and nothing else — the swarm
# skill still lands from its tag-pinned URL, which is what makes the recap
# count below a statement about one breakage.
#
# The stub writes the partial file curl itself would leave behind on a broken
# transfer, so the case tests the cleanup rather than curl's absence.
cp /usr/local/bin/curl /usr/local/bin/harness-curl-shim
cat > /usr/local/bin/curl <<'STUB'
#!/bin/bash
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    */docs/agents/*)
      for j in "${!args[@]}"; do
        if [ "${args[$j]}" = "-o" ]; then
          printf 'half a doc' > "${args[$((j + 1))]}"
        fi
      done
      echo "curl: (18) transfer closed with outstanding read data remaining" >&2
      exit 18
      ;;
  esac
done
exec /usr/local/bin/harness-curl-shim "$@"
STUB
chmod +x /usr/local/bin/curl
PRE

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
