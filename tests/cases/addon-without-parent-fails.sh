#!/bin/bash
# An add-on requested without its parent tool is the same class of error as a
# mistyped name and is raised in the same validation pass, so nobody ends up
# with a plugin installed and nothing to plug it into.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run kubectl gke-gcloud-auth-plugin

assert_status 1
assert_output_contains "gke-gcloud-auth-plugin"
assert_output_contains "gcloud"

if printf '%s\n%s\n' "${HARNESS_STDOUT}" "${HARNESS_STDERR}" | grep -qF -- "==> "; then
  harness_fail "expected validation to fail before any step ran"
fi
