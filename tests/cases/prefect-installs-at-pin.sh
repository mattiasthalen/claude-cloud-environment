#!/bin/bash
# prefect requested alone lands on PATH at the pinned version and the run says
# so in one verification line. Prefect comes from PyPI like snow does, so this
# pins the same contract for it: the uv install carried the PyPI pin, the shim
# landed somewhere every session's PATH already carries rather than in the
# installing shell's ~/.local/bin, and the binary that resulted actually runs.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin PREFECT_VERSION)

harness_run prefect

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path prefect
assert_output_contains "✓ prefect ${pin}"
assert_output_contains "✓ settings.json"

# The shim is on PATH for any session, not only for the shell that installed it:
# ~/.local/bin is not necessarily carried by a non-login shell, /usr/local/bin
# is. Asserting the resolved path is what tells those two apart.
printf '%s\n' "${HARNESS_TOOLS}" | grep -qx "prefect /usr/local/bin/prefect" ||
  harness_fail "expected prefect on PATH at /usr/local/bin/prefect, found: ${HARNESS_TOOLS:-<none>}"

# PyPI is not an apt vendor: a selection of prefect alone configures no
# repository and runs no apt at all.
assert_output_lacks "==> repository setup"
assert_output_lacks "==> apt-get update"
assert_output_lacks "==> apt-get install"
