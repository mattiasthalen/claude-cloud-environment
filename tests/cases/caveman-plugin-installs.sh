#!/bin/bash
# After a run, the caveman plugin is installed — not merely enabled.
#
# The two halves of "the session has caveman" fail independently. Enablement is
# a settings.json entry this script writes unconditionally, so it stays true
# even when the install died; the registry entry only exists if the CLI accepted
# the plugin's manifest. Upstream shipped a manifest listing its subagents as
# bare `agents/<name>.md` paths, which the CLI rejects with
# `agents: Invalid input`, and the run went red with the settings half still
# passing. This case asserts the half that went red, so the normalisation step
# that fixes it cannot be dropped silently.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_plugin_installed caveman@caveman
