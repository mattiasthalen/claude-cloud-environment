#!/bin/bash
set -euo pipefail

mkdir -p ~/.claude

# CLAUDE.md
cat > ~/.claude/CLAUDE.md << 'EOF'
- Always respond in caveman `full` mode per the caveman plugin ruleset.
EOF

# Plugins.
#
# `claude plugin install` installs a plugin but does NOT reliably enable it when
# run non-interactively (e.g. via `curl … | bash`): the plugin lands in the
# cache with `Status: disabled`, so its skills never load. An explicit
# `claude plugin enable` after each install flips it on and persists the
# enabledPlugins entry in settings.json.
#
# stdin is redirected from /dev/null on every plugin command so nothing reads
# leftover script bytes when this file is piped into bash.
#
# Each step is isolated with `|| true` so a single failure (e.g. a marketplace
# being unreachable, or `enable` reporting "already enabled") does not abort the
# rest under `set -e`.

# Add Matt Pocock's skills
claude plugin marketplace add mattpocock/skills </dev/null || true
claude plugin install mattpocock-skills@mattpocock </dev/null || true
claude plugin enable mattpocock-skills@mattpocock </dev/null || true

# Add caveman plugin
claude plugin marketplace add JuliusBrussee/caveman </dev/null || true
claude plugin install caveman@caveman </dev/null || true
claude plugin enable caveman@caveman </dev/null || true

# Lean Claude Code — written LAST.
# https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt
#
# The `claude plugin` commands above rewrite ~/.claude/settings.json to persist
# enabledPlugins / marketplaces, and that rewrite drops any keys they don't
# manage — including permissions.defaultMode. Writing settings.json here, after
# every plugin command has run, is what makes "auto" survive into the session.
# jq merges into whatever the plugin steps left behind so their entries are kept.
SETTINGS=~/.claude/settings.json
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
tmp=$(mktemp)
jq '
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
  | .disableBundledSkills = true
  | .disableWorkflows = true
  | .disableRemoteControl = true
  | .disableClaudeAiConnectors = true
  | .disableArtifact = true
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
