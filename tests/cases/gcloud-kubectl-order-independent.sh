#!/bin/bash
# The collision this whole design exists to prevent. The Google Cloud repository
# publishes an epoch-versioned kubectl (1:579.0.0-0) that outranks the
# pkgs.k8s.io build, so a per-tool installer would hand out a different binary
# depending on which order the tools were listed in. Collecting the selection
# first and installing once with every package explicitly pinned makes both
# orders produce the same packages, and makes the epoch-versioned build
# unreachable.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

gcloud_pin=$(harness_pin GCLOUD_VERSION)
kubectl_pin=$(harness_pin KUBECTL_VERSION)

harness_run gcloud kubectl
assert_status 0
first_gcloud=$(harness_pkg_version google-cloud-cli)
first_kubectl=$(harness_pkg_version kubectl)

harness_run kubectl gcloud
assert_status 0
second_gcloud=$(harness_pkg_version google-cloud-cli)
second_kubectl=$(harness_pkg_version kubectl)

[ "${first_gcloud}" = "${second_gcloud}" ] ||
  harness_fail "google-cloud-cli differs by argument order: '${first_gcloud}' then '${second_gcloud}'"
[ "${first_kubectl}" = "${second_kubectl}" ] ||
  harness_fail "kubectl differs by argument order: '${first_kubectl}' then '${second_kubectl}'"

[ "${first_gcloud}" = "${gcloud_pin}" ] ||
  harness_fail "expected google-cloud-cli at ${gcloud_pin}, dpkg reports '${first_gcloud:-<not installed>}'"

# The pkgs.k8s.io build, not the Google Cloud one: an epoch would show as a
# leading `1:` here, and it is what a plain unpinned install would have got.
[ "${first_kubectl}" = "${kubectl_pin}" ] ||
  harness_fail "expected kubectl at ${kubectl_pin} from pkgs.k8s.io, dpkg reports '${first_kubectl:-<not installed>}'"

assert_output_contains "✓ gcloud ${gcloud_pin%%-*}"
assert_output_contains "✓ kubectl v${kubectl_pin%%-*}"
