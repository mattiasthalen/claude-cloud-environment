#!/bin/bash
# After a run, settings.json parses as JSON and carries the keys the session
# depends on: the permission mode, both enabledPlugins entries, and the entries
# that leave one review path rather than two — the denied cavecrew subagents and
# the hidden caveman review skills. The plugin commands rewrite this file, so the
# shape it ends up with is the contract, not the shape the script's jq filter
# asks for.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_settings_jq '.permissions.defaultMode' 'auto'
assert_settings_jq '.enabledPlugins["mattpocock-skills@mattpocock"]' 'true'
assert_settings_jq '.enabledPlugins["caveman@caveman"]' 'true'

# Denied by name rather than by count, so adding an unrelated deny entry does
# not fail this case and dropping one of these does.
assert_settings_jq '.permissions.deny | index("Agent(cavecrew-builder)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Agent(cavecrew-investigator)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Agent(cavecrew-reviewer)") != null' 'true'

assert_settings_jq '.skillOverrides["cavecrew"]' 'off'
assert_settings_jq '.skillOverrides["caveman-review"]' 'off'
assert_settings_jq '.skillOverrides["caveman-commit"]' 'off'
assert_settings_jq '.skillOverrides["caveman-compress"]' 'off'
assert_settings_jq '.skillOverrides["caveman-help"]' 'off'
assert_settings_jq '.skillOverrides["caveman-stats"]' 'off'

# The level switcher is the one caveman skill left reachable. An override entry
# for it — of any value — would mean the hide list caught too much.
assert_settings_jq '.skillOverrides | has("caveman")' 'false'
