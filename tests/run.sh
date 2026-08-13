#!/bin/bash
# Runs the test suite. See docs/agents/testing.md.
#
#   tests/run.sh                      run every case
#   tests/run.sh settings-json-shape  run named cases only
#   tests/run.sh --tier quick         run one tier only
#   tests/run.sh --tier quick --list  print the cases that tier selects
#
# Every case declares its tier in a `# tier: quick` or `# tier: vendor` line —
# in the case file rather than in a list here or in a workflow, so that adding a
# case cannot silently leave a selection out of date. See docs/agents/testing.md
# for what the tiers are and which one gates a pull request.
set -uo pipefail

HARNESS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "${HARNESS_DIR}/lib.sh"

TIERS=(quick vendor)

tier=""
list_only=false
names=()
while [ $# -gt 0 ]; do
  case $1 in
    --tier)
      if [ $# -lt 2 ]; then
        echo "tests/run.sh: --tier takes a tier name (${TIERS[*]})" >&2
        exit 2
      fi
      tier=$2
      shift 2
      ;;
    --list)
      list_only=true
      shift
      ;;
    -*)
      echo "tests/run.sh: unknown option: $1" >&2
      exit 2
      ;;
    *)
      names+=("$1")
      shift
      ;;
  esac
done

# A tier name this runner knows, as opposed to a typo or a stale one.
known_tier() {
  local candidate
  for candidate in "${TIERS[@]}"; do
    [ "${candidate}" = "$1" ] && return 0
  done
  return 1
}

if [ -n "${tier}" ] && ! known_tier "${tier}"; then
  echo "tests/run.sh: unknown tier: ${tier} (${TIERS[*]})" >&2
  exit 2
fi

if [ -n "${tier}" ] && [ ${#names[@]} -gt 0 ]; then
  echo "tests/run.sh: --tier selects cases; naming them as well is ambiguous" >&2
  exit 2
fi

# The tier a case declares, or empty when it declares none or names one this
# runner does not know. Plain BRE, so a BSD sed reads the line the same way.
case_tier() {
  local declared
  declared=$(sed -n 's/^# tier: //p' "$1" | head -n 1)
  known_tier "${declared}" && printf '%s' "${declared}"
}

cases=()
if [ ${#names[@]} -gt 0 ]; then
  for name in "${names[@]}"; do
    file="${HARNESS_DIR}/cases/${name%.sh}.sh"
    if [ ! -f "${file}" ]; then
      echo "tests/run.sh: no such case: ${name}" >&2
      exit 2
    fi
    cases+=("${file}")
  done
else
  undeclared=()
  while IFS= read -r file; do
    declared=$(case_tier "${file}")
    if [ -z "${declared}" ]; then
      undeclared+=("$(basename "${file}" .sh)")
      # An untiered case still runs in an untiered run: a missing comment line
      # is a reason to fail a tier selection, not to stop running the case.
      [ -z "${tier}" ] && cases+=("${file}")
      continue
    fi
    if [ -z "${tier}" ] || [ "${declared}" = "${tier}" ]; then
      cases+=("${file}")
    fi
  done < <(find "${HARNESS_DIR}/cases" -name '*.sh' | sort)

  if [ ${#undeclared[@]} -gt 0 ]; then
    echo "tests/run.sh: these cases declare no known '# tier:' line (${TIERS[*]}):" >&2
    printf '  - %s\n' "${undeclared[@]}" >&2
    # Selecting a tier while some case belongs to none would silently drop it.
    [ -n "${tier}" ] && exit 2
  fi
fi

if [ "${list_only}" = true ]; then
  for file in "${cases[@]}"; do
    basename "${file}" .sh
  done
  exit 0
fi

# A hosted Claude Code session ships `dockerd` but starts nothing: PID 1 is the
# session's own supervisor rather than an init system, so the daemon sits
# installed and stopped and every run of this suite fails on the check below.
# Starting it here costs one attempt and removes a step no one can automate from
# inside a case.
#
# `setsid` and the redirections are load-bearing. A daemon started as a plain
# background job belongs to the calling shell's process group and is killed with
# it when that shell exits, which in an agent session means the daemon dies
# between one command and the next.
#
# The start is attempted only where it is safe to attempt: no daemon answering,
# a `dockerd` on PATH, and either root or passwordless sudo. Anywhere else —
# Docker Desktop, a rootless daemon, a CI runner with a socket mounted in — the
# original error stands and nothing is second-guessed.
harness_start_dockerd() {
  local log="${TMPDIR:-/tmp}/claude-cloud-environment-dockerd.log" sudo=() i

  command -v dockerd > /dev/null 2>&1 || return 1
  if [ "$(id -u)" -ne 0 ]; then
    sudo -n true 2> /dev/null || return 1
    sudo=(sudo -n)
  fi

  echo "==> no Docker daemon answering; starting dockerd (log: ${log})"
  setsid nohup "${sudo[@]}" dockerd >> "${log}" 2>&1 < /dev/null &
  disown 2> /dev/null || true

  for i in $(seq 1 30); do
    docker info > /dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

if ! docker info > /dev/null 2>&1 && ! harness_start_dockerd; then
  echo "tests/run.sh: no reachable Docker daemon; the suite runs each case in a container" >&2
  exit 2
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "tests/run.sh: jq is required on the host to assert on collected JSON" >&2
  exit 2
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
