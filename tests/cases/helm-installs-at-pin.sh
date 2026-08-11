#!/bin/bash
# helm requested alone lands on PATH at the pinned version and the run says so in
# one verification line. Same contract as the other release-archive tools: the
# download carried the pinned version, the binary landed somewhere every
# session's PATH already carries rather than in the installing shell's
# ~/.local/bin, and the binary that resulted actually runs.
#
# The verification line reads `✓ helm v<pin>`: helm reports its version with the
# leading `v` the lockfile drops, so the expected string is built with it here
# the same way the script builds it.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin HELM_VERSION)

harness_run helm

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path helm
assert_output_contains "✓ helm v${pin}"
assert_output_contains "✓ settings.json"

# On PATH for any session, not only for the shell that installed it:
# ~/.local/bin is not necessarily carried by a non-login shell, /usr/local/bin
# is. Asserting the resolved path is what tells those two apart.
printf '%s\n' "${HARNESS_TOOLS}" | grep -qx "helm /usr/local/bin/helm" ||
  harness_fail "expected helm on PATH at /usr/local/bin/helm, found: ${HARNESS_TOOLS:-<none>}"

# A release archive is not an apt vendor: a selection of helm alone configures
# no repository and runs no apt at all.
assert_output_lacks "==> repository setup"
assert_output_lacks "==> apt-get update"
assert_output_lacks "==> apt-get install"
