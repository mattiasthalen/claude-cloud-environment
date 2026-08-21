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
assert_output_contains "twg"
assert_output_contains "kubelogin"

assert_no_steps_ran

[ -z "${HARNESS_SETTINGS}" ] ||
  harness_fail "expected a failed validation to leave no settings.json"
