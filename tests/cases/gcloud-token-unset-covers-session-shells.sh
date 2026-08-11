#!/bin/bash
# A selection that names gcloud leaves the agent proxy's injected
# CLOUDSDK_AUTH_ACCESS_TOKEN unset in the shells a session actually starts.
# That variable carries a token Google rejects, so gcloud fails in a session
# that has perfectly good credentials until it is out of the environment.
#
# Both shells are the claim, because they read different files: a login shell
# reads /etc/profile and so the snippet under /etc/profile.d, an interactive
# non-login shell reads only /etc/bash.bashrc. The script's own row asserts the
# behaviour from inside the container; the assertions here are on the state it
# left behind.
#
# gcloud is stubbed at the pin so this stays a `quick` case: the presence guard
# skips the 883 MB install, while the write is gated on gcloud being *requested*
# and so still runs. The stub reports the pinned version, so verification passes
# and the run's exit code says something about the write rather than about a
# version mismatch.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin GCLOUD_VERSION)

harness_pre <<PRE
cat > /usr/local/bin/gcloud <<'STUB'
#!/bin/bash
echo "Google Cloud SDK ${pin%%-*}"
STUB
chmod +x /usr/local/bin/gcloud
PRE

harness_run gcloud

assert_status 0
assert_output_contains "==> gcloud: unset the injected CLOUDSDK_AUTH_ACCESS_TOKEN"
assert_output_contains "✓ gcloud CLOUDSDK_AUTH_ACCESS_TOKEN unset in login and interactive shells"
assert_output_lacks "==> apt-get install"

assert_gcloud_token_snippet_contains "unset CLOUDSDK_AUTH_ACCESS_TOKEN"
assert_bash_bashrc_sources_snippet 1

# The proxy's other CLOUDSDK_* variables are what route gcloud through it and
# make it trust its CA. Unsetting them would trade a broken auth path for a
# broken network path, so the snippet must name the token and nothing else.
for kept in CLOUDSDK_PROXY_TYPE CLOUDSDK_PROXY_ADDRESS CLOUDSDK_PROXY_PORT \
  CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE; do
  printf '%s\n' "${HARNESS_GCLOUD_TOKEN_SNIPPET}" | grep -qE "^[[:space:]]*unset .*${kept}" &&
    harness_fail "expected the snippet to leave ${kept} alone, got: ${HARNESS_GCLOUD_TOKEN_SNIPPET}"
done
