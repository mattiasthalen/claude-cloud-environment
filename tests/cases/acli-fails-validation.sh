#!/bin/bash
# The regression this repo cannot afford to lose silently: a box line that
# still names `acli` — the exact wording a stale environment might carry after
# the tool left the valid set — fails argument validation loudly, the same way
# any other unknown name does, naming the unknown tool and the valid set,
# before any repository setup or install work runs. No tombstone arm, no
# alias: `acli` is simply not in VALID_TOOLS any more, so it falls into the
# same unknown-tool arm as a typo. See docs/adr/0010-twg-replaces-acli.md for
# why it left rather than staying alongside `twg`.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run acli

assert_status 1
assert_output_contains "unknown tool: acli"
assert_output_contains "valid tools:"
assert_output_contains "twg"
assert_output_contains "gcloud"
assert_output_contains "kubelogin"

if printf '%s\n%s\n' "${HARNESS_STDOUT}" "${HARNESS_STDERR}" | grep -qF -- "==> "; then
  harness_fail "expected validation to fail before any step ran"
fi

printf '%s\n' "${HARNESS_TOOLS}" | grep -q '^acli ' &&
  harness_fail "expected no acli on PATH after a failed validation, found: ${HARNESS_TOOLS}"

[ -z "${HARNESS_SETTINGS}" ] ||
  harness_fail "expected a failed validation to leave no settings.json"
