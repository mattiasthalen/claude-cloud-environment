#!/bin/bash
# A PyPI pin that no longer resolves fails the run through the collected-failure
# path, naming the tool and the pin, and never falls back to latest — the whole
# reason pinning exists must not come back through the error path.
#
# The dead pin is arranged by shadowing uv with a stub that refuses to resolve,
# which is what PyPI would do for a yanked release; the script sees an install
# that failed with the pin in its step name either way.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin SNOW_VERSION)

harness_pre <<'PRE'
cat > "$(command -v uv)" <<'STUB'
#!/bin/bash
echo "error: distribution ${*: -1} not found" >&2
exit 1
STUB
PRE

harness_run snow

assert_status 1
assert_output_contains "uv tool install snowflake-cli==${pin}"
assert_output_contains "!!! step failed: uv tool install snowflake-cli==${pin}"

# No fallback to latest: nothing was installed, so nothing is on PATH.
printf '%s\n' "${HARNESS_TOOLS}" | grep -q '^snow ' &&
  harness_fail "expected no snow on PATH after a failed install, found: ${HARNESS_TOOLS}"

# The breakage is reported once, under the step that caused it. A tool whose
# install failed is not re-verified, so there is no second row for the same
# problem.
assert_output_lacks "✗ snow"
assert_output_lacks "verify snow"

# The rest of the run still happened: every step is attempted and the failures
# are recapped once at the end.
assert_output_contains "✓ settings.json"
assert_output_contains "1 step(s) failed"
