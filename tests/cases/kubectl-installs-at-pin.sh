#!/bin/bash
# kubectl requested alone lands on PATH at the pinned version and the run says
# so in one verification line. This is the whole contract of an apt tool: the
# repository was configured, the batched install carried the pin, and the binary
# that resulted actually runs.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin KUBECTL_VERSION)

harness_run kubectl

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path kubectl
assert_output_contains "✓ kubectl v${pin%%-*}"
assert_output_contains "✓ settings.json"

# One update and one install for the whole run, not one per tool.
updates=$(printf '%s\n' "${HARNESS_STDOUT}" | grep -c '^==> apt-get update$')
[ "${updates}" = "1" ] ||
  harness_fail "expected exactly one apt-get update step, saw ${updates}"

installs=$(printf '%s\n' "${HARNESS_STDOUT}" | grep -c '^==> apt-get install ')
[ "${installs}" = "1" ] ||
  harness_fail "expected exactly one apt-get install step, saw ${installs}"
