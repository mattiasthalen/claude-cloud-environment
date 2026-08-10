#!/bin/bash
# The presence guard covers the release-archive phase too: a second run over a
# container that already has kubelogin exits 0, downloads and extracts nothing at
# all, and still verifies the version that is there. Idempotency comes from the
# guard, not from a swallowed exit code.
#
# The first run is arranged in the container, through the same seam as the
# second — the script gets no test affordance for this.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin KUBELOGIN_VERSION)

harness_pre <<'PRE'
bash /harness/environment.sh kubelogin > /tmp/first-run.log 2>&1
PRE

harness_run kubelogin

assert_status 0
assert_tool_on_path kubelogin
assert_output_contains "✓ kubelogin v${pin}"
assert_output_lacks "==> release install"
