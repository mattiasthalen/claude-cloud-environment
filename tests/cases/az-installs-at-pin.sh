#!/bin/bash
# az requested alone lands on PATH at the pinned version and the run says so in
# one verification line: the Microsoft repository was registered, the batched
# install carried the pin, and the binary that resulted actually runs.
#
# This is the only az case, deliberately — the install is 636 MB.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin AZ_VERSION)

harness_run az

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path az
assert_output_contains "✓ az ${pin%%-*}"
assert_output_contains "✓ settings.json"
