#!/bin/bash
# Every name in the valid set parses. The selection is accepted whatever order
# it is listed in, because the parser only collects — the outcome cannot depend
# on argument order.
#
# This pins the parser, not the installers: the tools whose install and
# verification arms have not landed yet will fail further down, and this case
# deliberately says nothing about that. What it does say is that no name in the
# valid set is rejected as unknown, and that validation lets the run proceed
# past the argument pass.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run gcloud gke-gcloud-auth-plugin az kubectl snow acli

assert_first_line "environment.sh v$(harness_script_version)"
assert_output_lacks "unknown tool:"
assert_output_lacks "valid tools:"
assert_output_contains "==> apt-get update"
