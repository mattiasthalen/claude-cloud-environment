#!/bin/bash
# A second run over a container that already has prefect exits 0, runs no uv
# install at all, and still verifies the version that is there. Idempotency
# comes from the presence guard, not from a swallowed exit code.
#
# The first run is arranged in the container, through the same seam as the
# second — the script gets no test affordance for this.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin PREFECT_VERSION)

harness_pre <<'PRE'
bash /harness/environment.sh prefect > /tmp/first-run.log 2>&1
PRE

harness_run prefect

assert_status 0
assert_tool_on_path prefect
assert_output_contains "✓ prefect ${pin}"
assert_output_lacks "==> uv tool install"
