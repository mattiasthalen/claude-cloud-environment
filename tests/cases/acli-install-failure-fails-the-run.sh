#!/bin/bash
# An acli that cannot be installed fails the run through the same collected
# path as any other tool — unpinned does not mean best-effort. With the keyring
# directory unwritable the repository never gets configured, the batched install
# cannot find the package, and both failures are named in the one recap. acli is
# not then re-verified: a tool whose install already failed is reported once.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
rm -rf /etc/apt/keyrings
# A file where the keyring directory belongs, so creating it cannot succeed.
touch /etc/apt/keyrings
PRE

harness_run acli

assert_status 1
assert_output_contains "  - repository setup: atlassian"
assert_output_contains "  - apt-get install acli"
assert_output_lacks "✓ acli"
assert_output_lacks "verify acli"
