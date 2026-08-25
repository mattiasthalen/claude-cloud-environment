#!/bin/bash
# Everything outside this repo's raw base is somebody else's business and goes
# to the real curl untouched, so the stand-in cannot fail a step it was never
# meant to stand in for — every pinned CLI download in the script is such a
# fetch.
#
# The real curl is stubbed so the case observes delegation itself rather than
# whether some host on the internet answered.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_pre <<'PRE'
cat > /tmp/harness-stub-curl <<'STUB'
#!/bin/bash
prev=""
for arg in "$@"; do
  case "${prev}" in
    -o | --output) printf 'served by the real curl\n' > "${arg}" ;;
  esac
  prev="${arg}"
done
STUB
chmod +x /tmp/harness-stub-curl
printf '%s\n' /tmp/harness-stub-curl > /tmp/harness-real-curl

mkdir -p ~/.claude/docs/agents
curl -fsSL https://downloads.example.invalid/some/pinned/archive \
  -o ~/.claude/docs/agents/delegated.md
PRE

harness_run

assert_agent_doc_installed delegated.md
