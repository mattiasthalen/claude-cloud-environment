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
# Arms append through `want_apt` / `want_uv` rather than touching the arrays
# directly, so the presence guard is applied in one place instead of once per
# tool.
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
apt_tools=()
uv_pkgs=()

# Presence guard. A tool already on PATH contributes nothing to the install —
# that, and not a swallowed exit code, is what makes a re-run a no-op. The guard
# deliberately does not look at the version and does not self-heal a wrong one: a
# mismatch on a clean base is a condition to surface, and the verification block
# at the bottom of this file is what surfaces it.
tool_present() {
  command -v "$1" > /dev/null 2>&1
}

# want_apt <tool> <repo> <package[=pin]>
# Records the vendor repository the tool needs and the package the batched
# install should carry. apt_tools stays parallel to the selection so a failed
# install can be attributed back to the tools it was carrying.
want_apt() {
  local tool=$1 repo=$2 pkg=$3
  tool_present "${tool}" && return 0
  repos+=("${repo}")
  apt_pkgs+=("${pkg}")
  apt_tools+=("${tool}")
}

# want_uv <tool> <requirement>
want_uv() {
  local tool=$1 requirement=$2
  tool_present "${tool}" && return 0
  uv_pkgs+=("${requirement}")
}

for tool in "$@"; do
  requested_tools+=("${tool}")
  case "${tool}" in
    gcloud)                 want_apt gcloud google "google-cloud-cli=${GCLOUD_VERSION}" ;;
    gke-gcloud-auth-plugin) want_apt gke-gcloud-auth-plugin google "google-cloud-cli-gke-gcloud-auth-plugin=${GCLOUD_VERSION}" ;;
    az)                     want_apt az microsoft "azure-cli=${AZ_VERSION}" ;;
    kubectl)                want_apt kubectl k8s "kubectl=${KUBECTL_VERSION}" ;;
    snow)                   want_uv snow "snowflake-cli==${SNOW_VERSION}" ;;
    acli)                   want_apt acli atlassian acli ;;
    *)                      unknown_tools+=("${tool}") ;;
  esac
done

# True when the argument list contained this tool name.
tool_requested() {
  local wanted=$1 tool
  for tool in "${requested_tools[@]}"; do
    if [ "${tool}" = "${wanted}" ]; then
      return 0
    fi
  done
  return 1
}

# Validation. Every problem in the argument list is reported in this one pass,
# before any repository setup or install work, so a mistyped name costs a second
# rather than a minute and a failed run has installed nothing.
for tool in "${unknown_tools[@]}"; do
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

# ---------------------------------------------------------------------------
# Install
#
# Phased, not per-tool: every unique vendor repository named by the selection is
# set up once, then one `apt-get update` and one `apt-get install` carrying every
# pinned package. Batching is not only about cost — installing everything at once
# with every package explicitly pinned is what makes the outcome independent of
# argument order, which matters because the Google Cloud repository publishes an
# epoch-versioned `kubectl` that would otherwise outrank the pkgs.k8s.io build.
#
# Running as root means no `sudo`; `-y` everywhere, with DEBIAN_FRONTEND set as
# cheap insurance against a debconf prompt in a container with no terminal.
# ---------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

# Tools whose install failed. Verification skips these, so one breakage is
# reported once rather than twice under two names.
failed_tools=()

tool_install_failed() {
  local wanted=$1 tool
  for tool in ${failed_tools[@]+"${failed_tools[@]}"}; do
    if [ "${tool}" = "${wanted}" ]; then
      return 0
    fi
  done
  return 1
}

# Kubernetes: one repository per minor version, selected by KUBECTL_MINOR. The
# armoured key is used as-is rather than dearmoured — apt reads an ASCII-armoured
# `signed-by` file directly, which keeps `gnupg` off the prerequisite list for a
# base image this script does not control.
setup_repo_k8s() {
  local url="https://pkgs.k8s.io/core:/stable:/v${KUBECTL_MINOR}/deb"
  local keyring=/etc/apt/keyrings/kubernetes-apt-keyring.asc

  mkdir -p /etc/apt/keyrings || return 1
  curl -fsSL "${url}/Release.key" -o "${keyring}" || return 1
  chmod 644 "${keyring}" || return 1
  echo "deb [signed-by=${keyring}] ${url}/ /" \
    > /etc/apt/sources.list.d/kubernetes.list || return 1
  chmod 644 /etc/apt/sources.list.d/kubernetes.list
}

# Nothing to install means nothing to configure: with every requested tool
# already present, a re-run touches no repository and runs no apt at all.
if [ ${#apt_pkgs[@]} -gt 0 ]; then
  seen_repos=""
  for repo in "${repos[@]}"; do
    # A second tool from the same vendor is a no-op.
    case " ${seen_repos} " in
      *" ${repo} "*) continue ;;
    esac
    seen_repos="${seen_repos} ${repo}"

    case "${repo}" in
      k8s) run_step "repository setup: kubernetes" setup_repo_k8s ;;
      *)
        echo "environment.sh: no repository setup for vendor: ${repo}" >&2
        FAILED_STEPS+=("repository setup: ${repo}")
        ;;
    esac
  done

  run_step "apt-get update" apt-get update

  # The step name carries every package and its pin, so a pin that no longer
  # exists upstream is named in the recap as well as in apt's own error text.
  # The pin is always explicit: there is no unpinned fallback to fall back to.
  apt_failures_before=${#FAILED_STEPS[@]}
  run_step "apt-get install ${apt_pkgs[*]}" apt-get install -y "${apt_pkgs[@]}"
  if [ ${#FAILED_STEPS[@]} -ne "${apt_failures_before}" ]; then
    failed_tools+=("${apt_tools[@]}")
  fi
fi

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

# ---------------------------------------------------------------------------
# Verification. Read-only, so it sits below the settings write without breaking
# the settings-last constraint, and it reports the requested tools only — no
# "not requested" rows inviting anyone to wonder whether a skip was a failure.
# An empty selection still runs the block and says so explicitly, so an
# environment that deliberately asked for nothing does not read like one whose
# argument line got mangled.
#
# This is a second, independent gate: it can fail the session on its own. Each
# tool is invoked rather than located on PATH, because presence only proves a
# file landed while invocation proves the tool starts. The version it prints is
# compared against a string derived from the pin — exactly, not by containment,
# because "1.3" is contained in "1.34.10-1.1" — so there stays one source of
# truth per tool and no second EXPECTED variable to drift.
# ---------------------------------------------------------------------------

# verify_version <tool> <expected> <command...>
# One row. The command prints the version the tool reports and nothing else.
# A passing row carries only what was found; a failing one also carries the pin,
# so the interesting number appears exactly when it matters.
verify_version() {
  local tool=$1 expected=$2 actual
  shift 2

  if ! actual=$("$@" 2>/dev/null) || [ -z "${actual}" ]; then
    echo "✗ ${tool} did not run, expected ${expected}"
    FAILED_STEPS+=("verify ${tool}")
    return 0
  fi

  if [ "${actual}" = "${expected}" ]; then
    echo "✓ ${tool} ${actual}"
    return 0
  fi

  echo "✗ ${tool} ${actual}, expected ${expected}"
  FAILED_STEPS+=("verify ${tool}")
}

kubectl_reported_version() {
  kubectl version --client | sed -n 's/^Client Version: *//p' | head -n 1
}

# Read-back of the file written above: it has to parse as JSON and carry the
# keys a session depends on. `claude plugin list` is deliberately not consulted —
# its output format is not a contract.
verify_settings() {
  if jq -e '
    .permissions.defaultMode == "auto"
    and .enabledPlugins["mattpocock-skills@mattpocock"] == true
    and .enabledPlugins["caveman@caveman"] == true
  ' ~/.claude/settings.json > /dev/null 2>&1; then
    echo "✓ settings.json"
    return 0
  fi

  echo "✗ settings.json is missing, unparseable, or missing expected keys"
  FAILED_STEPS+=("verify settings.json")
}

if [ ${#requested_tools[@]} -eq 0 ]; then
  echo "✓ no tools requested"
fi

for tool in ${requested_tools[@]+"${requested_tools[@]}"}; do
  # A tool whose install already failed is not re-verified: its error text is
  # already in the log and its step is already in the recap.
  if tool_install_failed "${tool}"; then
    continue
  fi

  case "${tool}" in
    kubectl) verify_version kubectl "v${KUBECTL_VERSION%%-*}" kubectl_reported_version ;;
  esac
done

verify_settings

report_failures

exit 0
