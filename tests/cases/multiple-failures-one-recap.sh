#!/bin/bash
# Failures from different phases land in one list. A run whose plugin steps fail
# still reaches verification, a verification failure is collected the same way an
# install failure is, and the run ends with a single recap naming all of them and
# a single exit 1 — not an abort at the first thing that broke.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
cat > /root/.local/bin/claude <<'STUB'
#!/bin/bash
echo "stub claude: refusing $*" >&2
exit 1
STUB
chmod +x /root/.local/bin/claude

cat > /usr/local/bin/kubectl <<'STUB'
#!/bin/bash
echo "Client Version: v1.30.0"
STUB
chmod +x /usr/local/bin/kubectl
PRE

harness_run kubectl

assert_status 1
assert_output_contains "- marketplace add mattpocock/skills"
assert_output_contains "- plugin install caveman@caveman"
assert_output_contains "- verify kubectl"

recaps=$(printf '%s\n%s\n' "${HARNESS_STDOUT}" "${HARNESS_STDERR}" | grep -c 'step(s) failed:')
[ "${recaps}" = "1" ] ||
  harness_fail "expected one recap for the whole run, saw ${recaps}"
