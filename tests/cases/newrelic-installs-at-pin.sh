#!/bin/bash
# newrelic requested alone lands on PATH at the pinned version and the run says
# so in one verification line. Same contract as the other release-archive tool:
# the download carried the pinned version, the binary landed somewhere every
# session's PATH already carries rather than in the installing shell's
# ~/.local/bin, and the binary that resulted actually runs.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin NEWRELIC_VERSION)

harness_run newrelic

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path newrelic
assert_output_contains "✓ newrelic ${pin}"
assert_output_contains "✓ settings.json"

# On PATH for any session, not only for the shell that installed it:
# ~/.local/bin is not necessarily carried by a non-login shell, /usr/local/bin
# is. Asserting the resolved path is what tells those two apart.
printf '%s\n' "${HARNESS_TOOLS}" | grep -qx "newrelic /usr/local/bin/newrelic" ||
  harness_fail "expected newrelic on PATH at /usr/local/bin/newrelic, found: ${HARNESS_TOOLS:-<none>}"

# A release archive is not an apt vendor: a selection of newrelic alone
# configures no repository and runs no apt at all.
assert_output_lacks "==> repository setup"
assert_output_lacks "==> apt-get update"
assert_output_lacks "==> apt-get install"
