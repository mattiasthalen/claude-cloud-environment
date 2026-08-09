#!/bin/bash
# Not asserting acli's version is not the same as not checking acli. It is
# invoked like every other tool, so a build that put an acli in place that will
# not start is caught: the row fails, the failure joins the same collected list
# as an install failure, and the run exits 1 rather than handing a broken
# container to a session.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
cat > /usr/local/bin/acli <<'STUB'
#!/bin/bash
echo "acli: cannot execute" >&2
exit 1
STUB
chmod +x /usr/local/bin/acli
PRE

harness_run acli

assert_status 1
assert_output_contains "✗ acli did not run"
assert_output_contains "step(s) failed:"
assert_output_contains "  - verify acli"
