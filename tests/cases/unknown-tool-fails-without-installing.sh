#!/bin/bash
# A mistyped tool name fails in the first second: the run exits non-zero with a
# message naming the bad name and the valid set, and it does so before any
# other work happens — no plugin step ran, and no settings.json was left behind.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run kubectl kubctl

assert_status 1
assert_output_contains "unknown tool: kubctl"
assert_output_contains "gcloud"
assert_output_contains "gke-gcloud-auth-plugin"
assert_output_contains "az"
assert_output_contains "kubectl"
assert_output_contains "snow"
assert_output_contains "prefect"
assert_output_contains "acli"
assert_output_contains "kubelogin"

if printf '%s\n%s\n' "${HARNESS_STDOUT}" "${HARNESS_STDERR}" | grep -qF -- "==> "; then
  harness_fail "expected validation to fail before any step ran"
fi

[ -z "${HARNESS_SETTINGS}" ] ||
  harness_fail "expected a failed validation to leave no settings.json"
