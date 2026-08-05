#!/bin/bash
set -euo pipefail

# Add Matt Pocock's skills
claude plugin marketplace add mattpocock/skills
claude plugin install mattpocock-skills@mattpocock

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
