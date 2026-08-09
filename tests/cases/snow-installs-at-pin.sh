#!/bin/bash
# snow requested alone lands on PATH at the pinned version and the run says so
# in one verification line. This is the whole contract of the non-apt phase: the
# uv install carried the PyPI pin, the shim landed somewhere every session's
# PATH already carries rather than in the installing shell's ~/.local/bin, and
# the binary that resulted actually runs.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin SNOW_VERSION)

harness_run snow

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path snow
assert_output_contains "✓ snow ${pin}"
assert_output_contains "✓ settings.json"

# The shim is on PATH for any session, not only for the shell that installed it:
# ~/.local/bin is not necessarily carried by a non-login shell, /usr/local/bin
# is. Asserting the resolved path is what tells those two apart.
printf '%s\n' "${HARNESS_TOOLS}" | grep -qx "snow /usr/local/bin/snow" ||
  harness_fail "expected snow on PATH at /usr/local/bin/snow, found: ${HARNESS_TOOLS:-<none>}"

# PyPI is not an apt vendor: a selection of snow alone configures no repository
# and runs no apt at all.
assert_output_lacks "==> repository setup"
assert_output_lacks "==> apt-get update"
assert_output_lacks "==> apt-get install"
