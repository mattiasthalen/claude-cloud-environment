#!/bin/bash
# A clean run with no arguments succeeds: every step passes and the script
# exits 0, so the session it guards is allowed to start.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
