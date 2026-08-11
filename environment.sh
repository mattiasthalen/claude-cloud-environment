#!/bin/bash
set -euo pipefail

SCRIPT_VERSION=1.6.0

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
PREFECT_VERSION=3.8.2
# kubelogin is pinned without the leading `v` its release tags carry, so it reads
# like every other pin here. The tag, the archive URL and the version the binary
# reports are all built from this one value.
KUBELOGIN_VERSION=0.2.19
# newrelic is pinned without the leading `v` its release directory carries, for
# the same reason kubelogin is: the directory URL, the archive name, the
# checksums file and the version the binary reports are all built from this one
# value. Upstream also publishes a `currentVersion.txt` naming the latest
# release, which is exactly the floating source this block rules out.
NEWRELIC_VERSION=0.113.4
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
#   4. the install path the tool needs, which is one of three:
#      - apt, through `want_apt`: plus one repository setup arm, and only if the
#        vendor is not already used,
#      - PyPI, through `want_uv`: nothing else, PyPI is not an apt vendor,
#      - an upstream release archive, through `want_release`: plus one installer
#        function and one arm in the release install phase, because no two
#        projects lay their archives out the same way.
#
# Arms append through `want_apt` / `want_uv` / `want_release` rather than
# touching the arrays directly, so the presence guard is applied in one place
# instead of once per tool.
#
# The `case` below only appends; it installs nothing. Collecting the whole
# selection before installing anything is what makes the outcome independent of
# the order the tools were listed in, which is load-bearing: the Google Cloud
# repository publishes an epoch-versioned kubectl that would otherwise win or
# lose depending on argument order.
# ---------------------------------------------------------------------------

VALID_TOOLS="gcloud gke-gcloud-auth-plugin az kubectl snow prefect acli kubelogin newrelic"

requested_tools=()
unknown_tools=()
repos=()
apt_pkgs=()
apt_tools=()
uv_pkgs=()
uv_tools=()
release_pins=()
release_tools=()

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
# uv_tools stays parallel to uv_pkgs for the same reason apt_tools does: a failed
# install has to be attributable back to the tool it was carrying, so the
# verification block can skip a tool that never arrived.
want_uv() {
  local tool=$1 requirement=$2
  tool_present "${tool}" && return 0
  uv_pkgs+=("${requirement}")
  uv_tools+=("${tool}")
}

# want_release <tool> <version>
# A tool whose upstream ships neither an apt package nor a PyPI distribution,
# only a release archive — see the release-archive phase for where those are
# fetched from. release_tools stays parallel to release_pins for the
# same reason apt_tools and uv_tools do: a failed install has to be attributable
# back to the tool it was carrying. The pin travels with the tool so the step
# name can carry it, the way the apt and PyPI step names carry theirs.
want_release() {
  local tool=$1 version=$2
  tool_present "${tool}" && return 0
  release_pins+=("${version}")
  release_tools+=("${tool}")
}

for tool in "$@"; do
  requested_tools+=("${tool}")
  case "${tool}" in
    gcloud)                 want_apt gcloud google "google-cloud-cli=${GCLOUD_VERSION}" ;;
    gke-gcloud-auth-plugin) want_apt gke-gcloud-auth-plugin google "google-cloud-cli-gke-gcloud-auth-plugin=${GCLOUD_VERSION}" ;;
    az)                     want_apt az microsoft "azure-cli=${AZ_VERSION}" ;;
    kubectl)                want_apt kubectl k8s "kubectl=${KUBECTL_VERSION}" ;;
    snow)                   want_uv snow "snowflake-cli==${SNOW_VERSION}" ;;
    prefect)                want_uv prefect "prefect==${PREFECT_VERSION}" ;;
    acli)                   want_apt acli atlassian acli ;;
    kubelogin)              want_release kubelogin "${KUBELOGIN_VERSION}" ;;
    newrelic)               want_release newrelic "${NEWRELIC_VERSION}" ;;
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

# Microsoft: the Azure CLI repository, registered in the deb822 `.sources` form
# Microsoft documents rather than a one-line `.list` entry. The distribution
# codename is baked into the AZ_VERSION pin (`-1~noble`) as well as into Suites
# here, so the two move together. The armoured key is used as-is, as above.
#
# az extensions are not shipped by this script. When one is ever added it
# installs with `az extension add --system --version <version> -y`, so the
# extension is system-wide like everything else installed here rather than bound
# to root's $HOME.
setup_repo_microsoft() {
  local keyring=/etc/apt/keyrings/microsoft.asc

  mkdir -p /etc/apt/keyrings || return 1
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o "${keyring}" || return 1
  chmod 644 "${keyring}" || return 1
  cat > /etc/apt/sources.list.d/azure-cli.sources << EOF || return 1
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: noble
Components: main
Architectures: amd64
Signed-by: ${keyring}
EOF
  chmod 644 /etc/apt/sources.list.d/azure-cli.sources
}

# Atlassian: a single `stable` suite that carries exactly one version of acli,
# which is why acli is this script's unpinned exception. The armoured key is used
# as-is, as above and for the same reason.
setup_repo_atlassian() {
  local keyring=/etc/apt/keyrings/acli-archive-keyring.asc

  mkdir -p /etc/apt/keyrings || return 1
  curl -fsSL https://acli.atlassian.com/gpg/public-key.asc -o "${keyring}" || return 1
  chmod 644 "${keyring}" || return 1
  echo "deb [arch=amd64 signed-by=${keyring}] https://acli.atlassian.com/linux/deb stable main" \
    > /etc/apt/sources.list.d/acli.list || return 1
  chmod 644 /etc/apt/sources.list.d/acli.list
}

# Google Cloud: one repository for every gcloud package, base and components
# alike — the deb ships with the component manager disabled, so a component is
# an ordinary apt package from here. The armoured key is used as-is for the same
# reason as the Kubernetes one: apt reads a `signed-by` file in that form
# directly, which keeps `gnupg` off the prerequisite list.
setup_repo_google() {
  local url="https://packages.cloud.google.com/apt"
  local keyring=/etc/apt/keyrings/cloud.google.asc

  mkdir -p /etc/apt/keyrings || return 1
  curl -fsSL "${url}/doc/apt-key.gpg" -o "${keyring}" || return 1
  chmod 644 "${keyring}" || return 1
  echo "deb [signed-by=${keyring}] ${url} cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list || return 1
  chmod 644 /etc/apt/sources.list.d/google-cloud-sdk.list
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
      google) run_step "repository setup: google cloud" setup_repo_google ;;
      k8s) run_step "repository setup: kubernetes" setup_repo_k8s ;;
      microsoft) run_step "repository setup: microsoft" setup_repo_microsoft ;;
      atlassian) run_step "repository setup: atlassian" setup_repo_atlassian ;;
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

# ---------------------------------------------------------------------------
# PyPI installs. `uv tool install` for every tool whose upstream ships a Python
# distribution and no apt package — snow and prefect today. It is a phase rather
# than a per-tool special case, and it runs after the apt batch so the outcome
# stays independent of the order the tools were listed in. There is no
# repository setup arm to match: PyPI is not an apt vendor.
#
# UV_TOOL_BIN_DIR puts the shim in /usr/local/bin, which every session's PATH
# already carries, rather than uv's default ~/.local/bin, which a non-login
# shell need not. --python 3.12 is explicit so the interpreter is this script's
# decision rather than whatever uv happens to find. The requirement carries an
# exact `==` pin, so a pin that has gone from PyPI fails here — named, with its
# version, in the recap — instead of resolving to latest.
# ---------------------------------------------------------------------------

if [ ${#uv_pkgs[@]} -gt 0 ]; then
  for i in "${!uv_pkgs[@]}"; do
    uv_failures_before=${#FAILED_STEPS[@]}
    run_step "uv tool install ${uv_pkgs[i]}" \
      env UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 "${uv_pkgs[i]}"
    if [ ${#FAILED_STEPS[@]} -ne "${uv_failures_before}" ]; then
      failed_tools+=("${uv_tools[i]}")
    fi
  done
fi

# ---------------------------------------------------------------------------
# Release-archive installs. The third and last install phase, for a tool whose
# upstream publishes neither an apt package nor a Python distribution — only a
# built archive, on a GitHub release or on the vendor's own download host. It
# runs after the apt batch and the PyPI phase for the same reason that one does:
# every phase installs what the whole selection asked for, so the outcome does
# not depend on argument order.
#
# Which host an installer fetches from is its own decision and belongs in its own
# comment: what matters here is that the archive is a file to verify rather than
# a package a repository maintains.
#
# There is no shared installer, only a shared shape: no two projects name their
# archive, lay it out or checksum it the same way, so each tool gets its own
# function and the phase below is the dispatch. What every one of them owes:
#
#   - build every URL from the pin, so the lockfile stays the only place a
#     version is written,
#   - fail loudly and install nothing on a download that did not arrive whole —
#     a truncated archive must not become a binary on PATH,
#   - land the binary in /usr/local/bin, which every session's PATH already
#     carries, and not in ~/.local/bin, which a non-login shell need not,
#   - leave no partial install behind: the binary appears on PATH in one move,
#     after the archive has been verified and extracted, or not at all.
# ---------------------------------------------------------------------------

# kubelogin. Upstream ships one zip per platform plus a sha256 sidecar generated
# from it, and `kubelogin-linux-amd64.zip` carries the single binary at
# bin/linux_amd64/kubelogin. amd64 is the only architecture this script targets;
# a second one would be a second pin and a second archive, not a guess made here.
#
# The sidecar is what turns a half-delivered download into a failed step: `curl
# -f` catches a dead pin, a 404 or a proxy error page, and `sha256sum -c` catches
# the transfer that started fine and stopped early. Both run before anything is
# extracted, so a broken download costs a recap line and nothing else.
#
# The archive is unpacked with Python's `zipfile` module through `uv`, which the
# base image already carries and which the PyPI phase already depends on. The
# alternative was `apt-get install unzip` — an apt run in a selection that may
# have named no apt tool at all, which is exactly what this phase exists to
# avoid. `zipfile` does not carry the executable bit across, so `install` sets
# the mode; it also writes the destination in one move, which is what keeps a
# failure from leaving a half-written kubelogin on PATH.
install_kubelogin() {
  local version=$1
  local base="https://github.com/Azure/kubelogin/releases/download/v${version}"
  local archive=kubelogin-linux-amd64.zip
  local workdir

  workdir=$(mktemp -d) || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '${workdir}'" RETURN

  curl -fsSL "${base}/${archive}" -o "${workdir}/${archive}" || return 1
  curl -fsSL "${base}/${archive}.sha256" -o "${workdir}/${archive}.sha256" || return 1
  (cd "${workdir}" && sha256sum -c "${archive}.sha256") || return 1

  uv run --python 3.12 --no-project python -m zipfile \
    -e "${workdir}/${archive}" "${workdir}/unpacked" < /dev/null || return 1

  install -m 0755 "${workdir}/unpacked/bin/linux_amd64/kubelogin" /usr/local/bin/kubelogin
}

# newrelic. The New Relic CLI, which upstream ships as a release archive and as
# `.deb`/`.rpm` assets — assets, not repository packages, so the apt path this
# script uses for a vendor repository does not apply. New Relic's apt repository
# carries the infrastructure agent (`newrelic-infra`), a different tool this
# script does not install.
#
# The archives are taken from New Relic's own download host rather than from the
# GitHub release they are cut from. Both serve the same files, and this one is
# the vendor's documented install source, so the download does not depend on
# GitHub staying reachable for an environment that reaches New Relic anyway.
# Alongside them the host publishes `currentVersion.txt`; the pin exists so that
# file is not what decides which version an environment gets.
#
# The checksums arrive as one file covering every asset in the release rather
# than as a per-archive sidecar, so the archive's line is selected out of it
# before `sha256sum -c` reads it. Selecting on the whole second field rather
# than by substring is what keeps the Linux amd64 `.tar.gz` line from being
# confused with the `.deb` and `.rpm` lines that share its prefix. A pin that
# does not exist upstream fails earlier still: neither URL resolves.
#
# The binary sits at the root of the tarball, so extraction names it directly
# and nothing else in the archive — CHANGELOG.md, LICENSE, README.md — is
# unpacked. `install` writes the destination in one move, which is what keeps a
# failure from leaving a half-written newrelic on PATH.
#
# The tool is installed, not configured: no profile, API key, account or region.
# Those are credentials, and credentials are the box's business rather than this
# script's — see README.md.
install_newrelic() {
  local version=$1
  local base="https://download.newrelic.com/install/newrelic-cli/v${version}"
  local archive="newrelic-cli_${version}_Linux_x86_64.tar.gz"
  local checksums="newrelic-cli_${version}_checksums.txt"
  local workdir

  workdir=$(mktemp -d) || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '${workdir}'" RETURN

  curl -fsSL "${base}/${archive}" -o "${workdir}/${archive}" || return 1
  curl -fsSL "${base}/${checksums}" -o "${workdir}/${checksums}" || return 1
  (
    cd "${workdir}" &&
      awk -v archive="${archive}" '$2 == archive' "${checksums}" | sha256sum -c -
  ) || return 1

  tar -xzf "${workdir}/${archive}" -C "${workdir}" newrelic || return 1

  install -m 0755 "${workdir}/newrelic" /usr/local/bin/newrelic
}

if [ ${#release_tools[@]} -gt 0 ]; then
  for i in "${!release_tools[@]}"; do
    release_failures_before=${#FAILED_STEPS[@]}
    # The step name carries the tool and its pin, so a pin that no longer exists
    # upstream is named in the recap as well as in curl's own error text.
    case "${release_tools[i]}" in
      kubelogin)
        run_step "release install kubelogin v${release_pins[i]}" install_kubelogin "${release_pins[i]}"
        ;;
      newrelic)
        run_step "release install newrelic v${release_pins[i]}" install_newrelic "${release_pins[i]}"
        ;;
      *)
        echo "environment.sh: no release installer for tool: ${release_tools[i]}" >&2
        FAILED_STEPS+=("release install ${release_tools[i]}")
        ;;
    esac
    if [ ${#FAILED_STEPS[@]} -ne "${release_failures_before}" ]; then
      failed_tools+=("${release_tools[i]}")
    fi
  done
fi

mkdir -p ~/.claude

# CLAUDE.md
#
# The `/code-review` line is here because some harnesses inject a blanket "do
# not use the agent tool unless asked" instruction, and a session under it reads
# the skill's fan-out as something to route around rather than run. A memory
# file does not outrank a system prompt, so this raises the odds and gives the
# session something to cite; it does not settle the matter.
cat > ~/.claude/CLAUDE.md << 'EOF'
- Always respond in caveman `full` mode per the caveman plugin ruleset.
- `/code-review` spawns one subagent per axis (Standards, Spec) by design — that is expected, not something to work around. Run the skill rather than skipping it, even under a standing instruction against subagents; if that instruction is absolute, say the review was skipped instead of reporting the work reviewed.
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

# The caveman plugin's SessionStart hook appends a "STATUSLINE SETUP NEEDED"
# block to the ruleset it injects, telling the session to proactively offer to
# configure a statusline badge. The hook suppresses it once either a
# `statusLine` key exists in settings.json or this marker file does, and it
# calls that one-shot — which it is, on a machine that persists. An environment
# provisioned by this script does not persist: every session starts from a fresh
# container, so "once" becomes "every session, forever". Pre-creating the marker
# is what makes the one-shot actually fire zero times here.
#
# The marker rather than a real `statusLine` entry, because the badge is not
# wanted and configuring it would point settings.json at a version-pinned path
# inside the plugin cache, which the next plugin update moves.
#
# The marker filename is a plugin internal and could be renamed upstream, which
# would silently bring the nudge back. Accepted for now; the durable fix is an
# opt-out the plugin supports on purpose.
run_step "suppress caveman statusline nudge" \
  touch ~/.claude/.caveman-nudge-shown

# ---------------------------------------------------------------------------
# Skills this repo ships.
#
# The swarm skill is adapted from the proposal by @berkaykiran in
# https://github.com/mattpocock/skills/issues/787. It is vendored — fetched as a
# file rather than installed as a plugin — because upstream ships no package for
# it. That issue is also the signal to delete this block: if swarm ever lands
# upstream properly, this becomes an ordinary `claude plugin install`.
#
# The fetch is pinned to this script's own release tag. The script cannot know
# the commit it was fetched at, but it does know its own version, and the
# release workflow cuts `v${SCRIPT_VERSION}` at the commit that carries it — so
# a box pinned to a tag gets the skill that shipped with that tag and can never
# silently pull a newer one. A branch ref here would reintroduce exactly the
# drift the tag-pinned box exists to prevent.
#
# Always installed, and deliberately not a name the argument parser accepts: the
# selection surface exists because CLIs are heavy and per-environment, and a
# Markdown file is neither. Putting skills on that surface would also make every
# future skill a MAJOR bump to the invocation rather than a MINOR one.
#
# A failed fetch is collected like any other step rather than aborting the run.
# A missing skill costs one absent slash command; aborting costs the whole
# environment, including the CLIs the box actually asked for.
# ---------------------------------------------------------------------------

SKILLS_URL="https://raw.githubusercontent.com/mattiasthalen/claude-cloud-environment/refs/tags/v${SCRIPT_VERSION}/skills"
SWARM_SKILL=~/.claude/skills/swarm/SKILL.md

install_swarm_skill() {
  mkdir -p "$(dirname "${SWARM_SKILL}")" || return 1

  if curl -fsSL "${SKILLS_URL}/swarm/SKILL.md" -o "${SWARM_SKILL}"; then
    return 0
  fi

  # curl leaves the output file behind on a failed transfer, and a truncated
  # SKILL.md would verify as present. Removing it keeps absence honest.
  rm -f "${SWARM_SKILL}"
  return 1
}

# Tracked for the same reason failed_tools is: a skill whose fetch failed still
# gets its verification row, but the recap names the breakage once.
swarm_skill_install_failed=0
skill_failures_before=${#FAILED_STEPS[@]}
run_step "install swarm skill" install_swarm_skill
if [ ${#FAILED_STEPS[@]} -ne "${skill_failures_before}" ]; then
  swarm_skill_install_failed=1
fi

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
#
# The caveman plugin is enabled for its response style alone. Its review path —
# the three `cavecrew-*` subagents, the `cavecrew` skill that routes work to
# them, and `caveman-review` — is a second, tempting reviewer sitting next to
# `/code-review`, and a session told to review will take whichever is nearer.
# Denying both leaves one review path rather than two, which is the enforced
# half of what `~/.claude/CLAUDE.md` only asks for. The plugin's other skills go
# with them for a plainer reason: an environment provisioned by this script
# wants the response style and nothing else from the plugin, and every listed
# skill costs context in every session.
#
# Skills are denied rather than hidden with `skillOverrides`, which cannot
# express this: the override resolver returns "on" for any plugin-sourced skill
# before it reads settings at all, so an entry there would be inert whatever it
# said. Deny rules are checked at invocation instead, which is why the skill
# names carry the `caveman:` prefix the Skill tool takes.
#
# `caveman` itself is left reachable: it is the level switcher, and the response
# style it switches comes from the plugin's session hook rather than from any
# denied skill, so none of this turns the style off.
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
        "CronList",
        "Agent(cavecrew-builder)",
        "Agent(cavecrew-investigator)",
        "Agent(cavecrew-reviewer)",
        "Skill(caveman:cavecrew)",
        "Skill(caveman:caveman-review)",
        "Skill(caveman:caveman-commit)",
        "Skill(caveman:caveman-compress)",
        "Skill(caveman:caveman-help)",
        "Skill(caveman:caveman-init)",
        "Skill(caveman:caveman-stats)"
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

# verify_runs <tool> <command...>
# One row for a tool whose printed version is not comparable to a pin. Two kinds
# of tool land here: an add-on, which reports the version of what it plugs into
# rather than the apt version it was installed at, and acli, which has no pin to
# compare with at all — inventing one against a moving upstream would turn any
# acli release into a session-blocking failure for every environment that
# requested it. Exit zero and non-empty output is the whole assertion; for the
# add-on, which build landed is already guaranteed by the pin on the package.
# Invoking still catches the failure that matters here — a build that installed
# but will not start. The row carries the first line of what the tool printed,
# so it stays one line like every other.
verify_runs() {
  local tool=$1 actual
  shift

  if ! actual=$("$@" 2>/dev/null) || [ -z "${actual}" ]; then
    echo "✗ ${tool} did not run"
    FAILED_STEPS+=("verify ${tool}")
    return 0
  fi

  echo "✓ ${tool} ${actual%%$'\n'*}"
}

az_reported_version() {
  az version --query '"azure-cli"' --output tsv
}

snow_reported_version() {
  snow --version | sed -n 's/^Snowflake CLI version: *//p'
}

gcloud_reported_version() {
  gcloud version | sed -n 's/^Google Cloud SDK //p'
}

kubectl_reported_version() {
  kubectl version --client | sed -n 's/^Client Version: *//p'
}

# kubelogin prints a block, and the line that carries the release reads
# `git hash: v<version>/<commit>` — the tag the binary was built at, followed by
# the commit it was cut from. The tag alone is what the pin names, so the commit
# is dropped here rather than being worked into the expected string.
kubelogin_reported_version() {
  kubelogin --version | sed -n 's|^git hash: \([^/]*\).*|\1|p'
}

# newrelic prints one line, `newrelic version 0.113.4`, with no leading `v` — so
# the pin is compared as it is written in the lockfile, unlike kubelogin's.
newrelic_reported_version() {
  newrelic version | sed -n 's/^newrelic version //p'
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

# The shipped skill has no `--version` to report and nothing to invoke, so a
# non-empty installed file is the whole check. The row is printed either way —
# present or absent is what the block is for — but a fetch that already failed
# is not counted twice, the same way a tool whose install failed is not
# re-verified.
verify_swarm_skill() {
  if [ -s "${SWARM_SKILL}" ]; then
    echo "✓ swarm skill"
    return 0
  fi

  echo "✗ swarm skill is missing or empty"
  if [ "${swarm_skill_install_failed}" -eq 0 ]; then
    FAILED_STEPS+=("verify swarm skill")
  fi
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
    gcloud)                 verify_version gcloud "${GCLOUD_VERSION%%-*}" gcloud_reported_version ;;
    gke-gcloud-auth-plugin) verify_runs gke-gcloud-auth-plugin gke-gcloud-auth-plugin --version ;;
    az)                     verify_version az "${AZ_VERSION%%-*}" az_reported_version ;;
    kubectl)                verify_version kubectl "v${KUBECTL_VERSION%%-*}" kubectl_reported_version ;;
    snow)                   verify_version snow "${SNOW_VERSION}" snow_reported_version ;;
    prefect)                verify_version prefect "${PREFECT_VERSION}" prefect --version ;;
    acli)                   verify_runs acli acli --version ;;
    kubelogin)              verify_version kubelogin "v${KUBELOGIN_VERSION}" kubelogin_reported_version ;;
    newrelic)               verify_version newrelic "${NEWRELIC_VERSION}" newrelic_reported_version ;;
  esac
done

verify_swarm_skill
verify_settings

report_failures

exit 0
