#!/bin/bash
# The presence guard covers newrelic like every other tool: a second run over a
# container that already has it exits 0, downloads and extracts nothing at all,
# and still verifies the version that is there. Idempotency comes from the
# guard, not from a swallowed exit code.
#
# The first run is arranged in the container, through the same seam as the
# second — the script gets no test affordance for this.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin NEWRELIC_VERSION)

harness_pre <<'PRE'
bash /harness/environment.sh newrelic > /tmp/first-run.log 2>&1
PRE

harness_run newrelic

assert_status 0
assert_tool_on_path newrelic
assert_output_contains "✓ newrelic ${pin}"
assert_output_lacks "==> release install"
