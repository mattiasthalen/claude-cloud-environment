#!/bin/bash
# A release archive URL that does not resolve fails the run through the
# collected-failure path, naming the tool and the pin, and leaves nothing behind:
# a dead pin must not become a half-installed binary on PATH, and there is no
# fallback to whatever the latest release happens to be — the download host
# serves a `helm-latest-version` pointer that would make one easy, and the script
# does not read it.
#
# The dead pin is arranged by shadowing curl so the archive URL 404s, which is
# what get.helm.sh answers for a version that was never published; the script
# sees a download that failed with the pin in its step name either way. The
# checksum sidecar sits behind the same shadow, so a version that does not exist
# upstream reaches the network for neither of its two URLs; the archive is
# fetched first and returns, so the recap still carries one failure, not two.
# Everything that is not those two URLs goes to the harness curl, so the skill
# fetch is unaffected.
#
# Nothing installs here, so this case is cheap enough to gate a pull request.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin HELM_VERSION)

harness_pre <<'PRE'
mv /usr/local/bin/curl /usr/local/bin/harness-curl
cat > /usr/local/bin/curl <<'STUB'
#!/bin/bash
for arg in "$@"; do
  case "${arg}" in
    *helm-v*-linux-amd64.tar.gz*)
      echo "curl: (22) The requested URL returned error: 404" >&2
      exit 22
      ;;
  esac
done
exec /usr/local/bin/harness-curl "$@"
STUB
chmod +x /usr/local/bin/curl
PRE

harness_run helm

assert_status 1
assert_output_contains "==> release install helm v${pin}"
assert_output_contains "!!! step failed: release install helm v${pin}"
assert_output_contains "  - release install helm v${pin}"

# No fallback to latest, and no half-installed binary: nothing is on PATH.
printf '%s\n' "${HARNESS_TOOLS}" | grep -q '^helm ' &&
  harness_fail "expected no helm on PATH after a failed install, found: ${HARNESS_TOOLS}"

# The breakage is reported once, under the step that caused it. A tool whose
# install failed is not re-verified, so there is no second row for the same
# problem.
assert_output_lacks "✗ helm"
assert_output_lacks "verify helm"

# The rest of the run still happened: every step is attempted and the failures
# are recapped once at the end.
assert_output_contains "✓ settings.json"
assert_output_contains "1 step(s) failed"
