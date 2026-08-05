#!/bin/bash
set -euo pipefail

mkdir -p ~/.claude

# CLAUDE.md
cat > ~/.claude/CLAUDE.md << 'EOF'
- When reporting information to me, be extremely concise and sacrifice grammar for the sake of concision.
EOF

# Lean Claude Code
# https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt
cat > ~/.claude/settings.json << 'EOF'
{
  "permissions": {
    "deny": [
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
  },
  "disableBundledSkills": true,
  "disableWorkflows": true,
  "disableRemoteControl": true,
  "disableClaudeAiConnectors": true,
  "disableArtifact": true
}
EOF

# Plugins.
#
# Redirect stdin from /dev/null on every plugin command. When this script is run
# via `curl … | bash`, the script body itself occupies stdin, so `claude plugin
# install` reads leftover script bytes / EOF for its confirmation + settings
# merge step and the enable never persists. Feeding /dev/null gives it a clean,
# empty stdin so the install merges into settings.json non-interactively — no
# manual enabledPlugins map required.

# Each install is isolated with `|| true` so a single failing step does not
# abort the rest under `set -e`.

# Add Matt Pocock's skills
claude plugin marketplace add mattpocock/skills </dev/null || true
claude plugin install mattpocock-skills@mattpocock </dev/null || true

# Add caveman plugin
claude plugin marketplace add JuliusBrussee/caveman </dev/null || true
claude plugin install caveman@caveman </dev/null || true
