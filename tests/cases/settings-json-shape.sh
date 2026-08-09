#!/bin/bash
# After a run, settings.json parses as JSON and carries the keys the session
# depends on: the permission mode and both enabledPlugins entries. The plugin
# commands rewrite this file, so the shape it ends up with is the contract, not
# the shape the script's jq filter asks for.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_settings_jq '.permissions.defaultMode' 'auto'
assert_settings_jq '.enabledPlugins["mattpocock-skills@mattpocock"]' 'true'
assert_settings_jq '.enabledPlugins["caveman@caveman"]' 'true'
