#!/bin/bash
# The shipped skill is not on the argument surface. `swarm` is rejected as an
# unknown name like any other typo, and the valid-tools line does not offer it —
# the selection list exists for CLIs, which are heavy and per-environment, and a
# skill that every environment gets unconditionally has nothing to select.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run swarm

assert_status 1
assert_output_contains "unknown tool: swarm"

valid_line=$(printf '%s\n%s\n' "${HARNESS_STDOUT}" "${HARNESS_STDERR}" | grep -F 'valid tools:')
case "${valid_line}" in
  *swarm*) harness_fail "expected the valid-tools line to not offer swarm, got '${valid_line}'" ;;
esac

# Rejected in the argument pass, so nothing ran — including the skill install.
assert_output_lacks "==> install swarm skill"
assert_skill_absent swarm
