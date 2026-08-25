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

harness_pre <<'PRE'
# Shadow the harness curl, which would otherwise serve the skill. The shim is
# kept aside first and everything that is not a skill file is handed straight
# back to it, so this case fails the skill fetch and nothing else — the other
# artifacts the script ships still land from their tag-pinned URLs, which is
# what makes the recap count below a statement about one breakage.
cp /usr/local/bin/curl /usr/local/bin/harness-curl-shim
cat > /usr/local/bin/curl <<'STUB'
#!/bin/bash
for arg in "$@"; do
  case "${arg}" in
    *SKILL.md)
      echo "curl: (22) The requested URL returned error: 404" >&2
      exit 22
      ;;
  esac
done
exec /usr/local/bin/harness-curl-shim "$@"
STUB
chmod +x /usr/local/bin/curl
PRE

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
