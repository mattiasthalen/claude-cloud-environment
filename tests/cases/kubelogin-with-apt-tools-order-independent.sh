#!/bin/bash
# kubelogin sits in a selection next to apt tools without disturbing them: one
# run installs all three, each verified at its own pin, and where kubelogin
# appears in the argument list makes no difference — the phases install what the
# whole selection asked for, so nothing about the outcome depends on the order
# the names were typed in.
#
# Two runs rather than the same three-tool selection twice: az alone is a 636 MB
# install, and the order question is about the release-archive phase against the
# apt batch, which the cheap kubectl pairing answers just as well. So the first
# run pins the full selection with kubelogin first, and the second puts it last
# without paying for az again.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

kubelogin_pin=$(harness_pin KUBELOGIN_VERSION)
az_pin=$(harness_pin AZ_VERSION)
kubectl_pin=$(harness_pin KUBECTL_VERSION)

harness_run kubelogin az kubectl

assert_status 0
assert_tool_on_path kubelogin
assert_tool_on_path az
assert_tool_on_path kubectl
assert_output_contains "✓ kubelogin v${kubelogin_pin}"
assert_output_contains "✓ az ${az_pin%%-*}"
assert_output_contains "✓ kubectl v${kubectl_pin%%-*}"

first_kubectl=$(harness_pkg_version kubectl)

# kubelogin last rather than first. The apt batch still carries the pkgs.k8s.io
# kubectl — an epoch would show as a leading `1:` here — and kubelogin still
# lands from its own phase.
harness_run kubectl kubelogin

assert_status 0
assert_tool_on_path kubelogin
assert_tool_on_path kubectl
assert_output_contains "✓ kubelogin v${kubelogin_pin}"
assert_output_contains "✓ kubectl v${kubectl_pin%%-*}"

second_kubectl=$(harness_pkg_version kubectl)

[ "${first_kubectl}" = "${second_kubectl}" ] ||
  harness_fail "kubectl differs by argument order: '${first_kubectl}' then '${second_kubectl}'"
[ "${first_kubectl}" = "${kubectl_pin}" ] ||
  harness_fail "expected kubectl at ${kubectl_pin} from pkgs.k8s.io, dpkg reports '${first_kubectl:-<not installed>}'"
