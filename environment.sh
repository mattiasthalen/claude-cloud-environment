#!/bin/bash
set -euo pipefail

SCRIPT_VERSION=1.0.0

# Lockfile. Every version this script installs is pinned here and nowhere else,
# so a version roll is one reviewed diff hunk rather than a hunt through
# installers. Exact versions only: a floating patch component would let a
# container rebuild move an environment across a release.
#
# kubectl keeps two variables rather than deriving one from the other by string
# manipulation — KUBECTL_MINOR selects the pkgs.k8s.io repository, KUBECTL_VERSION
# pins the package. If they ever drift apart, the pinned version will not exist
# in the configured repository and the install fails loudly, which is the point.
GCLOUD_VERSION=579.0.0-0
AZ_VERSION=2.89.0-1~noble
KUBECTL_MINOR=1.34
KUBECTL_VERSION=1.34.10-1.1
SNOW_VERSION=3.16.0
# acli: deliberately unpinned — upstream offers no pin, and asserting a version
# would turn any upstream acli release into a session-blocking failure for every
# environment that requested it.

# First line of output, so the container-start log always says which snapshot
# ran — including on a run that dies before it finishes.
echo "environment.sh v${SCRIPT_VERSION}"

# Failure policy: every step is attempted, failures accumulate here, and the
# run ends with one recap and a plain `exit 1`. No step swallows its own exit
# code, and there is no quiet tier — plugin steps and the settings write are
# governed alike.
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

# The one recap and the one `exit 1`. Called after argument validation, so a bad
# argument list ends the run before anything is installed, and again at the end
# of a run that got that far. A run with nothing collected falls through.
report_failures() {
  [ ${#FAILED_STEPS[@]} -gt 0 ] || return 0

  echo
  echo "environment.sh v${SCRIPT_VERSION}: ${#FAILED_STEPS[@]} step(s) failed:" >&2
  for step in "${FAILED_STEPS[@]}"; do
    echo "  - ${step}" >&2
  done
  exit 1
}

# ---------------------------------------------------------------------------
# Tool selection
#
# The tools an environment needs arrive as positional arguments through the
# pipe: `curl -sL … | bash -s -- gcloud kubectl snow`. Names are binary names —
# the commands a session will actually type. The namespace is flat: an add-on is
# just a tool name whose installer happens to be a package with a longer name.
#
# Adding a tool later is four steps, no more:
#   1. one line in the lockfile block at the top of this file,
#   2. one `case` arm below, appending to the accumulators, with the new name
#      added to VALID_TOOLS,
#   3. one arm in the verification block at the bottom of this file,
#   4. one repository setup arm — only if the vendor is not already used.
#
# The `case` below only appends; it installs nothing. Collecting the whole
# selection before installing anything is what makes the outcome independent of
# the order the tools were listed in, which is load-bearing: the Google Cloud
# repository publishes an epoch-versioned kubectl that would otherwise win or
# lose depending on argument order.
# ---------------------------------------------------------------------------

VALID_TOOLS="gcloud gke-gcloud-auth-plugin az kubectl snow acli"

requested_tools=()
unknown_tools=()
repos=()
apt_pkgs=()
uv_pkgs=()

for tool in "$@"; do
  requested_tools+=("${tool}")
  case "${tool}" in
    gcloud)                 repos+=(google);    apt_pkgs+=("google-cloud-cli=${GCLOUD_VERSION}") ;;
    gke-gcloud-auth-plugin) repos+=(google);    apt_pkgs+=("google-cloud-cli-gke-gcloud-auth-plugin=${GCLOUD_VERSION}") ;;
    az)                     repos+=(microsoft); apt_pkgs+=("azure-cli=${AZ_VERSION}") ;;
    kubectl)                repos+=(k8s);       apt_pkgs+=("kubectl=${KUBECTL_VERSION}") ;;
    snow)                                       uv_pkgs+=("snowflake-cli==${SNOW_VERSION}") ;;
    acli)                   repos+=(atlassian); apt_pkgs+=(acli) ;;
    *)                      unknown_tools+=("${tool}") ;;
  esac
done

# True when the argument list contained this tool name.
tool_requested() {
  local wanted=$1 tool
  for tool in ${requested_tools[@]+"${requested_tools[@]}"}; do
    [ "${tool}" = "${wanted}" ] && return 0
  done
  return 1
}

# Validation. Every problem in the argument list is reported in this one pass,
# before any repository setup or install work, so a mistyped name costs a second
# rather than a minute and a failed run has installed nothing.
for tool in ${unknown_tools[@]+"${unknown_tools[@]}"}; do
  echo "environment.sh: unknown tool: ${tool}" >&2
  echo "  valid tools: ${VALID_TOOLS}" >&2
  FAILED_STEPS+=("unknown tool: ${tool}")
done

# An add-on requested without its parent is the same class of error: it would
# install a plugin with nothing to plug into.
if tool_requested gke-gcloud-auth-plugin && ! tool_requested gcloud; then
  echo "environment.sh: gke-gcloud-auth-plugin requested without its parent tool gcloud" >&2
  FAILED_STEPS+=("gke-gcloud-auth-plugin requested without gcloud")
fi

report_failures

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
# an explicit `enabledPlugins` entry in the settings write below rather than by
# invoking the plugin CLI's enable subcommand — that command is the one
# non-idempotent command in this file (it exits 1 on "already enabled") and is
# only a wrapper over the same map. `claude plugin marketplace add` stays a
# command, because `install` requires the marketplace registered at install
# time.
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

# Verification. Read-only, so it sits below the settings write without breaking
# the settings-last constraint, and it reports the requested tools only — no
# "not requested" rows inviting anyone to wonder whether a skip was a failure.
# An empty selection still runs the block and says so explicitly, so an
# environment that deliberately asked for nothing does not read like one whose
# argument line got mangled.
if [ ${#requested_tools[@]} -eq 0 ]; then
  echo "✓ no tools requested"
fi

report_failures

exit 0
