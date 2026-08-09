#!/bin/bash
# Every name in the valid set parses. The selection is accepted whatever order
# it is listed in, because the parser only collects — the outcome cannot depend
# on argument order.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run gcloud gke-gcloud-auth-plugin az kubectl snow acli

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
