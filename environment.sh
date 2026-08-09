#!/bin/bash
set -euo pipefail

SCRIPT_VERSION=1.0.0

# First line of output, so the container-start log always says which snapshot
# ran — including on a run that dies before it finishes.
echo "environment.sh v${SCRIPT_VERSION}"

# Failure policy: every step is attempted, failures accumulate here, and the
# run ends with one recap and a plain `exit 1`. No `|| true` anywhere, and no
# quiet tier — plugin steps and the settings write are governed alike.
FAILED_STEPS=()

# Run a step, streaming its output so the underlying error text appears next to
# the step that produced it. A non-zero exit records the step name and lets the
# run continue; the recap at the end names step names only.
run_step() {
  local name=$1
  shift

  echo "==> ${name}"
  if "$@"; then
    return 0
  fi

  echo "!!! step failed: ${name}" >&2
  FAILED_STEPS+=("${name}")
  return 0
}

mkdir -p ~/.claude

# CLAUDE.md
cat > ~/.claude/CLAUDE.md << 'EOF'
- Always respond in caveman `full` mode per the caveman plugin ruleset.
EOF

# Plugins.
#
# `claude plugin install` installs a plugin but does NOT enable it when run
# non-interactively (e.g. via `curl … | bash`): the plugin lands in the cache
# with `Status: disabled`, so its skills never load. Enablement is expressed as
# an explicit `enabledPlugins` entry in the settings write below rather than a
# `claude plugin enable` call — that command is the one non-idempotent command
# in this file (it exits 1 on "already enabled") and is only a wrapper over the
# same map. `claude plugin marketplace add` stays a command, because `install`
# requires the marketplace registered at install time.
#
# stdin is redirected from /dev/null on every plugin command so nothing reads
# leftover script bytes when this file is piped into bash.

# Add Matt Pocock's skills
run_step "marketplace add mattpocock/skills" \
  claude plugin marketplace add mattpocock/skills </dev/null
run_step "plugin install mattpocock-skills@mattpocock" \
  claude plugin install mattpocock-skills@mattpocock </dev/null

# Add caveman plugin
run_step "marketplace add JuliusBrussee/caveman" \
  claude plugin marketplace add JuliusBrussee/caveman </dev/null
run_step "plugin install caveman@caveman" \
  claude plugin install caveman@caveman </dev/null

# Lean Claude Code — written LAST.
# https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt
#
# The `claude plugin` commands above rewrite ~/.claude/settings.json to persist
# enabledPlugins / marketplaces, and that rewrite drops any keys they don't
# manage — including permissions.defaultMode. Writing settings.json here, after
# every plugin command has run, is what makes "auto" survive into the session.
# jq merges into whatever the plugin steps left behind so their entries are kept.
#
# The enabledPlugins entries are assigned `true` explicitly rather than deleted
# when off, because `claude plugin disable` writes `false` rather than removing
# the key — an absent key and a `false` key are not the same state.
write_settings() {
  local settings=~/.claude/settings.json
  local tmp

  [ -f "$settings" ] || echo '{}' > "$settings"

  tmp=$(mktemp)
  if jq '
    .permissions.defaultMode = "auto"
    | .permissions.deny = [
        "EnterPlanMode",
        "ExitPlanMode",
        "DesignSync",
        "NotebookEdit",
        "SendMessage",
        "PushNotification",
        "RemoteTrigger",
        "ReportFindings",
        "ScheduleWakeup",
        "AskUserQuestion",
        "CronCreate",
        "CronDelete",
        "CronList"
      ]
    | .enabledPlugins["mattpocock-skills@mattpocock"] = true
    | .enabledPlugins["caveman@caveman"] = true
    | .disableBundledSkills = true
    | .disableWorkflows = true
    | .disableRemoteControl = true
    | .disableClaudeAiConnectors = true
    | .disableArtifact = true
  ' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
    return 0
  fi

  rm -f "$tmp"
  return 1
}

run_step "write settings.json" write_settings

if [ ${#FAILED_STEPS[@]} -gt 0 ]; then
  echo
  echo "environment.sh v${SCRIPT_VERSION}: ${#FAILED_STEPS[@]} step(s) failed:" >&2
  for step in "${FAILED_STEPS[@]}"; do
    echo "  - ${step}" >&2
  done
  exit 1
fi

exit 0
