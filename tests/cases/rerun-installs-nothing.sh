#!/bin/bash
# Re-running the script over a container that already has the requested tools
# exits 0 and installs nothing. Idempotency comes from the presence guard, not
# from a swallowed exit code: with nothing left to install there is no
# repository setup, no apt-get update and no apt-get install at all.
#
# The first run is arranged in the container, through the same seam as the
# second — the script gets no test affordance for this.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin KUBECTL_VERSION)

harness_pre <<'PRE'
bash /harness/environment.sh kubectl > /tmp/first-run.log 2>&1
PRE

harness_run kubectl

assert_status 0
assert_tool_on_path kubectl
assert_output_contains "✓ kubectl v${pin%%-*}"
assert_output_lacks "==> apt-get update"
assert_output_lacks "==> apt-get install"
assert_output_lacks "==> repository setup"
