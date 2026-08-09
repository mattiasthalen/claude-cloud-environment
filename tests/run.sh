#!/bin/bash
# Runs the test suite. See docs/agents/testing.md.
#
#   tests/run.sh                    run every case
#   tests/run.sh settings-json-shape  run named cases only
set -uo pipefail

HARNESS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "${HARNESS_DIR}/lib.sh"

if ! docker info > /dev/null 2>&1; then
  echo "tests/run.sh: no reachable Docker daemon; the suite runs each case in a container" >&2
  exit 2
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "tests/run.sh: jq is required on the host to assert on collected JSON" >&2
  exit 2
fi

cases=()
if [ $# -gt 0 ]; then
  for name in "$@"; do
    file="${HARNESS_DIR}/cases/${name%.sh}.sh"
    if [ ! -f "${file}" ]; then
      echo "tests/run.sh: no such case: ${name}" >&2
      exit 2
    fi
    cases+=("${file}")
  done
else
  mapfile -t cases < <(find "${HARNESS_DIR}/cases" -name '*.sh' | sort)
fi

harness_build_image || exit 2

passed=0
failed=()
for file in "${cases[@]}"; do
  name=$(basename "${file}" .sh)
  echo
  echo "==> case: ${name}"
  if bash "${file}"; then
    echo "PASS ${name}"
    passed=$((passed + 1))
  else
    echo "FAIL ${name}" >&2
    failed+=("${name}")
  fi
done

echo
echo "${passed} passed, ${#failed[@]} failed"
if [ ${#failed[@]} -gt 0 ]; then
  for name in "${failed[@]}"; do
    echo "  - ${name}" >&2
  done
  exit 1
fi
