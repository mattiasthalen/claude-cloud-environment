#!/bin/bash
# After a run, settings.json parses as JSON and carries the keys the session
# depends on: the permission mode, both enabledPlugins entries, the built-in
# tools denied to keep their schemas out of the system prompt, the entries that
# leave one review path rather than two — the denied cavecrew subagents and
# caveman review skills — and the two allowed repo-attachment tools. The plugin
# commands rewrite this file, so the shape it ends up with is the contract, not
# the shape the script's jq filter asks for.
#
# The two groups of deny entries are not equivalent. Denying a built-in removes
# its schema from the prompt; denying a skill does not hide it, and refuses it
# only at invocation. Both land in the same array, so this file asserts them the
# same way, but see docs/adr/0002 before reading either group as a saving.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_settings_jq '.permissions.defaultMode' 'auto'
assert_settings_jq '.enabledPlugins["mattpocock-skills@mattpocock"]' 'true'
assert_settings_jq '.enabledPlugins["caveman@caveman"]' 'true'

# The allow list, pinned by exact literal rather than by pattern or count —
# capitals included, because a wrong-cased rule matches nothing and says nothing.
# See the comment above `write_settings` in environment.sh for why that silence
# makes this the assertion to have.
assert_settings_jq '.permissions.allow | index("mcp__Claude_Code_Remote__add_repo") != null' 'true'
assert_settings_jq '.permissions.allow | index("mcp__Claude_Code_Remote__register_repo_root") != null' 'true'

# Denied by name rather than by count, so adding an unrelated deny entry does
# not fail this case and dropping one of these does.
#
# What this proves is the file, not the behaviour: no case here starts a Claude
# session, so a rule that landed correctly and a rule Claude honours are
# different claims and only the first is tested. That is the same limit every
# settings assertion in this file lives with.

# The built-in half of the deny list — the entries that keep a tool schema out
# of the system prompt. Asserted by name for the same reason the caveman entries
# below are: the plugin commands rewrite this file, so the shape it ends up with
# is the contract.
assert_settings_jq '.permissions.deny | index("EnterPlanMode") != null' 'true'
assert_settings_jq '.permissions.deny | index("ExitPlanMode") != null' 'true'
assert_settings_jq '.permissions.deny | index("NotebookEdit") != null' 'true'
assert_settings_jq '.permissions.deny | index("PushNotification") != null' 'true'
assert_settings_jq '.permissions.deny | index("RemoteTrigger") != null' 'true'
assert_settings_jq '.permissions.deny | index("ReportFindings") != null' 'true'
assert_settings_jq '.permissions.deny | index("ScheduleWakeup") != null' 'true'
assert_settings_jq '.permissions.deny | index("CronCreate") != null' 'true'
assert_settings_jq '.permissions.deny | index("CronDelete") != null' 'true'
assert_settings_jq '.permissions.deny | index("CronList") != null' 'true'

# `DesignSync` is not a Claude Code tool. It sat in this list until an audit
# checked every entry against the tool reference, and a deny rule naming no
# known tool earns a startup warning rather than doing anything. Asserted absent
# so the typo cannot return.
assert_settings_jq '.permissions.deny | index("DesignSync") == null' 'true'

# Denied once, reverted deliberately: `AskUserQuestion` is the only way a
# session under defaultMode "auto" reaches its user, and `SendMessage` is the
# only way it resumes a subagent rather than respawning one. Both are the kind
# of entry a later tidy-up of this list would restore without noticing what it
# costs, so their absence is asserted as explicitly as the caveman entries'
# presence.
assert_settings_jq '.permissions.deny | index("AskUserQuestion") == null' 'true'
assert_settings_jq '.permissions.deny | index("SendMessage") == null' 'true'

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
