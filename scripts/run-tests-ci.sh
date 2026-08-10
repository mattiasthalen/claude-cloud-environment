#!/bin/bash
# Test-suite seam for CI, shared by both test workflows.
#
# Usage: scripts/run-tests-ci.sh [tests/run.sh arguments ...]
#
# Runs the suite with whatever selection it is given and turns the runner's exit
# code into a workflow annotation, because the two non-zero codes need different
# fixes: `2` means the suite could not run at all — the runner or its host is
# wrong — and `1` means it ran and a case failed, which is a finding about the
# tree. The exit code is passed through unchanged either way.
#
# This is one script rather than logic inlined in a workflow because the same
# handling runs on `pull_request` and again on the schedule. Two copies could
# disagree; one cannot.
set -uo pipefail

HARNESS=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tests/run.sh

status=0
"${HARNESS}" "$@" || status=$?

case ${status} in
  0) ;;
  2) echo "::error::the suite could not run — see the message above (Docker daemon, jq, tier declarations, or the base image build)" ;;
  *) echo "::error::the suite ran and reported failures — see the recap above" ;;
esac

exit "${status}"
