#!/bin/bash
# The reason git-lfs is installable at all: the filters are registered
# system-wide, so a clone brings down real blobs instead of pointer files.
#
# The package alone does not do this. A binary on PATH with no filters
# registered leaves an LFS-tracked file as a pointer a few hundred bytes long,
# and whatever reads it fails with an error naming neither LFS nor the cause —
# which is the failure this tool was added to prevent. So the config is asserted
# where a session can see it, /etc/gitconfig rather than root's own home, and
# then the filters are asserted by what they do: a commit that goes in as a
# pointer and comes back out as the real bytes.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run git-lfs

assert_status 0
assert_output_contains "==> git lfs install --system"

# System-wide, so the session's user inherits it.
assert_system_git_config filter.lfs.smudge
assert_system_git_config filter.lfs.clean
assert_system_git_config filter.lfs.process

# And they work, not merely appear.
assert_lfs_round_trip
