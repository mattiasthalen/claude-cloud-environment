#!/bin/bash
# Runs inside the test container. Not for direct use — tests/lib.sh mounts it.
#
# Contract with the harness, all under /harness (read-only) and /out (writable):
#   /harness/environment.sh  the script under test
#   /harness/pre.sh          optional, sourced-as-run before the script, so a
#                            case can arrange container state (e.g. shadow a
#                            binary) without the script gaining a test hook
#   /out/stdout /out/stderr  captured streams
#   /out/status              the script's exit code
#   /out/settings.json       ~/.claude/settings.json as the run left it, if any
#
# Nothing here asserts. It only runs the script and collects what it left
# behind, so assertions live in the case files on the host.
set -u

if [ -f /harness/pre.sh ]; then
  bash /harness/pre.sh
fi

bash /harness/environment.sh "$@" > /out/stdout 2> /out/stderr
status=$?
echo "${status}" > /out/status

# Collected container state. Add to this block when a case needs to assert on
# something else the script leaves behind.
if [ -f "${HOME}/.claude/settings.json" ]; then
  cp "${HOME}/.claude/settings.json" /out/settings.json
fi

# Always zero: a failing script is a result to report, not a harness error.
exit 0
