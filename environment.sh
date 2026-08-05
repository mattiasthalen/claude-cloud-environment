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
  "disableArtifact": true,
  "enabledPlugins": {
    "mattpocock-skills@mattpocock": true,
    "caveman@caveman": true
  }
}
EOF

# Plugins are installed AFTER the config files above. We enable them explicitly
# via the enabledPlugins map written above rather than relying on `claude plugin
# install` to merge those entries into settings.json — that merge did not happen
# non-interactively, leaving plugins cached but disabled.
#
# Each marketplace/install is isolated with `|| true` so that a single failing
# step does not abort the rest of the script (set -e would otherwise skip every
# subsequent plugin).

# Add Matt Pocock's skills
claude plugin marketplace add mattpocock/skills || true
claude plugin install mattpocock-skills@mattpocock || true

# Add caveman plugin
claude plugin marketplace add JuliusBrussee/caveman || true
claude plugin install caveman@caveman || true
