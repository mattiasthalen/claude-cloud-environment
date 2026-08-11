#!/bin/bash
# The token unset is opt-in with gcloud, like every other action the script
# takes. A selection that never named gcloud gets no snippet under
# /etc/profile.d and no line appended to /etc/bash.bashrc — the script's first
# unconditional write to a machine's shell startup files is not something an
# environment gets for asking for nothing.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_output_contains "✓ no tools requested"
assert_output_lacks "CLOUDSDK_AUTH_ACCESS_TOKEN"

assert_gcloud_token_snippet_absent
assert_bash_bashrc_sources_snippet 0
