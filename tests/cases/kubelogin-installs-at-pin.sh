#!/bin/bash
# kubelogin requested alone lands on PATH at the pinned version and the run says
# so in one verification line. This is the whole contract of the release-archive
# phase: the download carried the pinned tag, the binary landed somewhere every
# session's PATH already carries rather than in the installing shell's
# ~/.local/bin, and the binary that resulted actually runs.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin KUBELOGIN_VERSION)

harness_run kubelogin

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path kubelogin
assert_output_contains "✓ kubelogin v${pin}"
assert_output_contains "✓ settings.json"

# On PATH for any session, not only for the shell that installed it:
# ~/.local/bin is not necessarily carried by a non-login shell, /usr/local/bin
# is. Asserting the resolved path is what tells those two apart.
printf '%s\n' "${HARNESS_TOOLS}" | grep -qx "kubelogin /usr/local/bin/kubelogin" ||
  harness_fail "expected kubelogin on PATH at /usr/local/bin/kubelogin, found: ${HARNESS_TOOLS:-<none>}"

# A GitHub release is not an apt vendor: a selection of kubelogin alone
# configures no repository and runs no apt at all.
assert_output_lacks "==> repository setup"
assert_output_lacks "==> apt-get update"
assert_output_lacks "==> apt-get install"
