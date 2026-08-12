#!/bin/bash
# A git-lfs binary on PATH whose filters are not registered fails the run.
#
# This is the state the presence guard would otherwise wave through: the guard
# looks only for the command, so a base image that ever ships the binary without
# the filters contributes no install — and the tool would then be reported as
# verified while every session still got pointer files. Verification asserts the
# outcome instead of the binary, so the run fails and names the actual defect.
#
# The stub accepts `install` and does nothing, which is exactly the shape of the
# failure being tested: the step runs, reports success, and leaves no filters
# behind.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
cat > /usr/local/bin/git-lfs <<'STUB'
#!/bin/bash
case "$1" in
  version) echo "git-lfs/3.4.1 (GitHub; linux amd64; go 1.20.3)" ;;
esac
exit 0
STUB
chmod +x /usr/local/bin/git-lfs
PRE

harness_run git-lfs

assert_status 1
assert_output_contains "✗ git-lfs filters are not registered system-wide"
assert_output_contains "  - verify git-lfs"
assert_system_git_config_lacks filter.lfs.smudge

# The presence guard held: nothing was installed, and the failure is the
# configuration rather than a missing package.
assert_output_lacks "==> apt-get install"

# The version row is never reached — a tool whose filters are missing is not a
# working tool, whatever version it reports.
assert_output_lacks "✓ git-lfs"
