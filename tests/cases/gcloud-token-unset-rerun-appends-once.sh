#!/bin/bash
# Re-running over a container the script already set up leaves one source line
# in /etc/bash.bashrc, not a second copy of it. The snippet itself is rewritten
# rather than appended to, so it cannot grow either; the bashrc line is the one
# that could, which is why it is guarded and why this case counts it.
#
# The first run is arranged in the container through the same seam as the
# second, and gcloud is stubbed for both so this stays a `quick` case.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

pin=$(harness_pin GCLOUD_VERSION)

harness_pre <<PRE
cat > /usr/local/bin/gcloud <<'STUB'
#!/bin/bash
echo "Google Cloud SDK ${pin%%-*}"
STUB
chmod +x /usr/local/bin/gcloud

bash /harness/environment.sh gcloud > /tmp/first-run.log 2>&1
PRE

harness_run gcloud

assert_status 0
assert_gcloud_token_snippet_contains "unset CLOUDSDK_AUTH_ACCESS_TOKEN"
assert_bash_bashrc_sources_snippet 1
