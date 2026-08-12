#!/bin/bash
# git-lfs requested alone lands on PATH at the pinned release series and the run
# says so in one verification line.
#
# It is the script's only tool from the plain Ubuntu archive, so no repository is
# configured for it — the absence of a `repository setup` line is part of the
# claim, not an omission. The pin is the other half: it carries a trailing `*`
# because the archive supersedes the Debian revision in place, so the assertion
# is on the release series the package landed at rather than on a full version
# string that a security update would move.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run git-lfs

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path git-lfs
assert_output_contains "✓ git-lfs $(harness_pin GIT_LFS_VERSION | sed 's/\*$//')"
assert_output_contains "✓ settings.json"

# From the Ubuntu archive, which the base image already has: the package is
# installed and no vendor repository was set up to get it.
assert_output_contains "==> apt-get install git-lfs=$(harness_pin GIT_LFS_VERSION)"
assert_output_lacks "==> repository setup"

# The pin holds the release series, and the revision below it is the archive's
# business rather than this repo's.
case "$(harness_pkg_version git-lfs)" in
  "$(harness_pin GIT_LFS_VERSION | sed 's/\*$//')"*) ;;
  *) harness_fail "expected an installed git-lfs matching $(harness_pin GIT_LFS_VERSION), got '$(harness_pkg_version git-lfs)'" ;;
esac
