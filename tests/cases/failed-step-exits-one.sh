#!/bin/bash
# A run in which a step fails exits 1 and ends with a recap naming the step, so
# a broken container refuses to hand itself to a session and the cause is at the
# bottom of the log rather than somewhere in it.
#
# The failure is arranged in the container, by shadowing the CLI the plugin
# steps call, rather than by any test affordance in the script.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
cat > /root/.local/bin/claude <<'STUB'
#!/bin/bash
echo "stub claude: refusing $*" >&2
exit 1
STUB
chmod +x /root/.local/bin/claude
PRE

harness_run

assert_status 1
assert_output_contains "step(s) failed:"
assert_output_contains "- marketplace add mattpocock/skills"
assert_output_contains "- plugin install caveman@caveman"
