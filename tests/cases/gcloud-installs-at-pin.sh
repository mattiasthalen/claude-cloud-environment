#!/bin/bash
# gcloud and its one add-on, requested together. This is the expensive case for
# the Google Cloud vendor (883 MB), so it carries every claim that only a real
# install can settle: the repository is set up once, both packages land at the
# same pin through the single batched install, gcloud verifies against that pin,
# and the add-on's row asserts invocability only — it prints a Kubernetes client
# version, which is not comparable to the apt pin.
# tier: vendor
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin GCLOUD_VERSION)

harness_run gcloud gke-gcloud-auth-plugin

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
assert_tool_on_path gcloud
assert_tool_on_path gke-gcloud-auth-plugin
assert_output_contains "✓ gcloud ${pin%%-*}"
assert_output_contains "✓ settings.json"

# Each package carries its own `=` pin: components declare no versioned Depends
# and the base package only Suggests them, so apt matches nothing on its own.
for pkg in google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin; do
  installed=$(harness_pkg_version "${pkg}")
  [ "${installed}" = "${pin}" ] ||
    harness_fail "expected ${pkg} at ${pin}, dpkg reports '${installed:-<not installed>}'"
done

# The add-on row is invocability only. A version comparison would fail the
# session every time the bundled Kubernetes client version moved.
addon_row=$(printf '%s\n' "${HARNESS_STDOUT}" | grep -F 'gke-gcloud-auth-plugin' | grep -E '^[✓✗]')
[ -n "${addon_row}" ] ||
  harness_fail "expected a verification row for gke-gcloud-auth-plugin"
case "${addon_row}" in
  *expected*) harness_fail "expected the add-on row to carry no expected version, got '${addon_row}'" ;;
esac

# Two packages from one vendor: one repository setup, one update, one install.
setups=$(printf '%s\n' "${HARNESS_STDOUT}" | grep -c '^==> repository setup: ')
[ "${setups}" = "1" ] ||
  harness_fail "expected exactly one repository setup step, saw ${setups}"

installs=$(printf '%s\n' "${HARNESS_STDOUT}" | grep '^==> apt-get install ')
[ "$(printf '%s\n' "${installs}" | grep -c .)" = "1" ] ||
  harness_fail "expected exactly one apt-get install step, saw: ${installs}"
case "${installs}" in
  *"google-cloud-cli=${pin}"*) ;;
  *) harness_fail "expected the batched install to carry google-cloud-cli=${pin}, got '${installs}'" ;;
esac
case "${installs}" in
  *"google-cloud-cli-gke-gcloud-auth-plugin=${pin}"*) ;;
  *) harness_fail "expected the batched install to carry the add-on at ${pin}, got '${installs}'" ;;
esac
