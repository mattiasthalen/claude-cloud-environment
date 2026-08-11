#!/bin/bash
# After a run, ~/.claude/.caveman-nudge-shown exists.
#
# The caveman plugin's SessionStart hook nags every session to set up a
# statusline badge until either a `statusLine` key or this marker exists. The
# hook treats that as a one-shot, which holds on a machine that persists and
# fails here: every session in a provisioned environment starts from a fresh
# container, so without the marker the nudge fires forever.
#
# Asserted by name because the marker's existence is its entire content, and
# because the name is a plugin internal — an upstream rename is the way this
# fix dies silently, and this case is what would say so.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_claude_dotfile .caveman-nudge-shown
