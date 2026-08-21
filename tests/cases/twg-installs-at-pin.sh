#!/bin/bash
# twg requested alone lands on PATH at the pinned version and the run says so in
# one verification line. Same contract as the other release tools: the download
# came from the vendor's own host and carried the pinned version, the checksum
# held before anything landed, the binary landed somewhere every session's PATH
# already carries rather than in the installing shell's ~/.local/bin, and the
# binary that resulted actually runs.
#
# The verification line reads `✓ twg <pin>` with no leading `v`: twg reports the
# bare version, so the expected string is the pin exactly as the lockfile writes
# it.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin TWG_VERSION)

harness_run twg

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path twg
assert_output_contains "==> release install twg v${pin}"
assert_output_contains "✓ twg ${pin}"
assert_output_contains "✓ settings.json"

# On PATH for any session, not only for the shell that installed it:
# ~/.local/bin — where the vendor's own installer puts it — is not necessarily
# carried by a non-login shell, /usr/local/bin is. Asserting the resolved path
# is what tells those two apart.
printf '%s\n' "${HARNESS_TOOLS}" | grep -qx "twg /usr/local/bin/twg" ||
  harness_fail "expected twg on PATH at /usr/local/bin/twg, found: ${HARNESS_TOOLS:-<none>}"

# A vendor download host is not an apt vendor: a selection of twg alone
# configures no repository and runs no apt at all — in particular not the
# Atlassian repository that acli beside it would have set up.
assert_output_lacks "==> repository setup"
assert_output_lacks "==> apt-get update"
assert_output_lacks "==> apt-get install"
