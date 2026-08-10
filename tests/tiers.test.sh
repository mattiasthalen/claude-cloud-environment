#!/bin/bash
# Test cases for tier selection in tests/run.sh.
#
#   Run: tests/tiers.test.sh
#
# The suite itself needs a Docker daemon; this does not. It exercises the part
# of the runner that decides *which* cases run — `--tier` plus `--list` — so the
# rule that keeps a tier from drifting away from tests/cases/ is itself checked
# on a host with no daemon, which is where the drift would be introduced.
#
# The runner is asked what a tier selects rather than the case files being
# re-scanned here, so this cannot pass by reimplementing what it is testing.
#
# No `-e`: a non-zero exit from the runner is the subject of some of these
# assertions, not a reason to abort the run.
set -uo pipefail

readonly HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RUN="${HARNESS_DIR}/run.sh"

failures=0
ran=0
LAST_OUTPUT=""

# expect <expected-exit> <description> -- <args ...>
# Runs the runner with those arguments; asserts on the exit code and leaves the
# output in LAST_OUTPUT for the caller to assert on further.
expect() {
  local expected=$1 description=$2
  shift 3

  ran=$((ran + 1))

  local output status
  output=$("${RUN}" "$@" 2>&1 </dev/null)
  status=$?
  LAST_OUTPUT=$output

  if [[ $status -eq $expected ]]; then
    echo "✓ ${description}"
    return 0
  fi

  echo "✗ ${description}: expected exit ${expected}, got ${status}"
  echo "  output: ${output}"
  failures=$((failures + 1))
  return 1
}

# expect_listed <case> / expect_unlisted <case>
# Assert on the case list LAST_OUTPUT holds.
expect_listed() {
  ran=$((ran + 1))
  if printf '%s\n' "${LAST_OUTPUT}" | grep -qx -- "$1"; then
    echo "✓ the selection lists $1"
    return 0
  fi
  echo "✗ the selection does not list $1"
  echo "  selection: ${LAST_OUTPUT}"
  failures=$((failures + 1))
}

expect_unlisted() {
  ran=$((ran + 1))
  if printf '%s\n' "${LAST_OUTPUT}" | grep -qx -- "$1"; then
    echo "✗ the selection lists $1, which it should not"
    echo "  selection: ${LAST_OUTPUT}"
    failures=$((failures + 1))
    return 1
  fi
  echo "✓ the selection excludes $1"
}

count_of() { printf '%s\n' "$1" | grep -c .; }

# --- the quick tier selects the cases that install no CLI ------------------

expect 0 "--list --tier quick runs without a Docker daemon" -- --list --tier quick
quick_list=${LAST_OUTPUT}
expect_listed swarm-skill-installs-at-tag-pin
expect_listed clean-run-exits-zero
expect_listed settings-json-shape
expect_unlisted az-installs-at-pin
expect_unlisted gcloud-installs-at-pin
expect_unlisted snow-installs-at-pin

expect 0 "--list --tier vendor lists the expensive selections" -- --list --tier vendor
vendor_list=${LAST_OUTPUT}
expect_listed az-installs-at-pin
expect_listed gcloud-installs-at-pin
expect_listed snow-installs-at-pin

# --- the tiers cover tests/cases/ ------------------------------------------
# The drift guard: a case added without a tier line is in neither tier, and this
# is what says so before a workflow silently stops running it.

expect 0 "--list with no tier lists every case" -- --list
all_count=$(count_of "${LAST_OUTPUT}")
file_count=$(find "${HARNESS_DIR}/cases" -name '*.sh' | wc -l | tr -d ' ')
partition=$(( $(count_of "${quick_list}") + $(count_of "${vendor_list}") ))

ran=$((ran + 1))
if [ "${partition}" = "${all_count}" ] && [ "${all_count}" = "${file_count}" ]; then
  echo "✓ the tiers partition tests/cases/"
else
  echo "✗ the tiers do not partition tests/cases/"
  echo "  quick + vendor = ${partition}, every case = ${all_count}, files = ${file_count}"
  failures=$((failures + 1))
fi

# --- misuse ----------------------------------------------------------------

expect 2 "an unknown tier is refused" -- --list --tier nonsense
expect 2 "--tier takes a tier name" -- --list --tier
expect 2 "--tier together with named cases is refused" -- --list --tier quick clean-run-exits-zero
expect 2 "an unknown option is refused" -- --list --nonsense

echo
if [ ${failures} -eq 0 ]; then
  echo "${ran} passed"
  exit 0
fi
echo "${ran} run, ${failures} failed" >&2
exit 1
