#!/bin/bash
# acli requested alone lands on PATH from the Atlassian repository and the run
# says so in one verification line. It is the script's single unpinned tool, so
# the install carries no `=version` and the verification line carries no
# expected-version text — only what the binary reported about itself.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run acli

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path acli
assert_output_contains "==> repository setup: atlassian"
assert_output_contains "✓ acli "
assert_output_contains "✓ settings.json"

# The package is named with no pin: appending one would fail against a
# repository that publishes exactly one version.
assert_output_contains "==> apt-get install acli"
assert_output_lacks "acli="
