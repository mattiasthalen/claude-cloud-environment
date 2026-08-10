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
#
# What this proves is the file, not the behaviour: no case here starts a Claude
# session, so a rule that landed correctly and a rule Claude honours are
# different claims and only the first is tested. That is the same limit every
# settings assertion in this file lives with.
assert_settings_jq '.permissions.deny | index("Agent(cavecrew-builder)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Agent(cavecrew-investigator)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Agent(cavecrew-reviewer)") != null' 'true'

assert_settings_jq '.permissions.deny | index("Skill(caveman:cavecrew)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Skill(caveman:caveman-review)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Skill(caveman:caveman-commit)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Skill(caveman:caveman-compress)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Skill(caveman:caveman-help)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Skill(caveman:caveman-init)") != null' 'true'
assert_settings_jq '.permissions.deny | index("Skill(caveman:caveman-stats)") != null' 'true'

# The level switcher is the one caveman skill left reachable. A deny entry for
# it would mean the list caught too much — and `caveman-*` names make that easy
# to do by accident, so it is asserted rather than assumed.
assert_settings_jq '.permissions.deny | index("Skill(caveman:caveman)") == null' 'true'

# skillOverrides cannot express any of this: the override resolver returns "on"
# for plugin-sourced skills before reading settings. An entry here would be a
# silent no-op, so its absence is the assertion.
assert_settings_jq 'has("skillOverrides")' 'false'
