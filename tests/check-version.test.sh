#!/bin/bash
# Test cases for the version check seam.
#
# Run: tests/check-version.test.sh
#
# The seam is invoked exactly as CI and CD invoke it — a version value and a
# tag set in, an exit code and a message out. Assertions are on the exit code
# and on the message naming the offending value; nothing here reaches inside
# the script.
#
# No `-e`: a non-zero exit from the script under test is the subject of most of
# these assertions, not a reason to abort the run.
set -uo pipefail

readonly CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/check-version.sh"

failures=0
ran=0
LAST_OUTPUT=""

# expect <expected-exit> <description> -- <args ...>
expect() {
  local expected=$1 description=$2
  shift 3

  ran=$((ran + 1))

  local output status
  output=$("$CHECK" "$@" 2>&1 </dev/null)
  status=$?

  if [[ $status -eq $expected ]]; then
    echo "✓ ${description}"
    LAST_OUTPUT=$output
    return 0
  fi

  echo "✗ ${description}: expected exit ${expected}, got ${status}"
  echo "  output: ${output}"
  failures=$((failures + 1))
  LAST_OUTPUT=$output
  return 1
}

# expect_output <substring> <description>  — asserts against the last run.
expect_output() {
  local needle=$1 description=$2

  ran=$((ran + 1))

  if [[ $LAST_OUTPUT == *"$needle"* ]]; then
    echo "✓ ${description}"
    return 0
  fi

  echo "✗ ${description}: output does not contain '${needle}'"
  echo "  output: ${LAST_OUTPUT}"
  failures=$((failures + 1))
  return 1
}

# Well-formedness.
expect 1 "a version missing a field fails" -- 1.2
expect_output "1.2" "the malformed-version message names the offending value"
expect 1 "a v-prefixed version fails" -- v1.2.3
expect_output "v1.2.3" "the v-prefix message names the offending value"
expect 1 "a non-numeric version fails" -- 1.2.3-rc1
expect_output "1.2.3-rc1" "the non-numeric message names the offending value"
expect 1 "an empty version fails" -- ""

# Empty tag set.
expect 0 "any well-formed version passes with no tags at all" -- 1.0.0
expect 0 "a version passes when no tag is of release form" -- 1.0.0 v1 v1.2 nightly

# Monotonicity.
expect 1 "a version equal to the highest tag fails" -- 1.2.0 v1.0.0 v1.2.0
expect_output "v1.2.0" "the equal-version message names the highest tag"
expect 1 "a version below the highest tag fails" -- 1.1.9 v1.2.0
expect 0 "a version above the highest tag passes" -- 1.2.1 v1.0.0 v1.2.0
expect 0 "tag order does not matter" -- 1.2.1 v1.2.0 v1.0.0

# Numeric comparison per field.
expect 0 "1.10.0 ranks above 1.9.0" -- 1.10.0 v1.9.0
expect 1 "1.9.0 ranks below 1.10.0" -- 1.9.0 v1.10.0
expect 0 "2.0.0 ranks above 1.99.99" -- 2.0.0 v1.99.99
expect 1 "0.9.0 ranks below 1.0.0" -- 0.9.0 v1.0.0

# Usage.
expect 1 "no arguments at all fails" --

echo
if ((failures > 0)); then
  echo "${failures} of ${ran} assertions failed"
  exit 1
fi

echo "all ${ran} assertions passed"
