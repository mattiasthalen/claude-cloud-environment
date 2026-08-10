#!/bin/bash
# The first line of output is the SCRIPT_VERSION echo, so the container-start
# log always says which snapshot ran.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_first_line "environment.sh v$(harness_script_version)"
