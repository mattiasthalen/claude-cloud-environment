#!/bin/bash
# Runs inside the test container. Not for direct use — tests/lib.sh mounts it.
#
# Contract with the harness, all under /harness (read-only) and /out (writable):
#   /harness/environment.sh  the script under test
#   /harness/skills/         the skill sources the working tree would ship
#   /harness/pre.sh          optional, sourced-as-run before the script, so a
#                            case can arrange container state (e.g. shadow a
#                            binary) without the script gaining a test hook
#   /out/stdout /out/stderr  captured streams
#   /out/status              the script's exit code
#   /out/settings.json       ~/.claude/settings.json as the run left it, if any
#   /out/CLAUDE.md           ~/.claude/CLAUDE.md as the run left it, if any
#   /out/claude-dotfiles     the dotfile names directly under ~/.claude, one
#                            per line, empty when there are none
#   /out/installed-plugins.json
#                            ~/.claude/plugins/installed_plugins.json as the run
#                            left it, if any
#   /out/tools               the tools the run left on PATH
#   /out/skills              the skills the run left installed
#   /out/packages            the apt packages the container has
#   /out/gitconfig-system    /etc/gitconfig as the run left it
#   /out/lfs-blob            the committed form of an LFS-tracked file
#   /out/lfs-worktree        the checked-out form of that same file
#
# Nothing here asserts. It only runs the script and collects what it left
# behind, so assertions live in the case files on the host.
set -u

# ---------------------------------------------------------------------------
# The release-tag stand-in.
#
# The script fetches the skills it ships from its own release tag, and the
# working tree under test is by definition unreleased: the tag its
# SCRIPT_VERSION names does not exist on GitHub yet, so that fetch could only
# ever 404 in here. This shim stands in for the tag the release will cut, and
# serves what that tag will carry — the working tree's own copy of the file,
# mounted at /harness/skills.
#
# It answers exactly one URL: the tag-pinned one built from the script's own
# SCRIPT_VERSION. Any other URL for a skill file — a branch ref, another tag —
# is refused rather than passed through to the network, where a branch ref would
# happily succeed. So a case that sees a skill land has thereby seen the pinned
# URL, and the pin is asserted by behaviour rather than by reading the script.
# Every URL that is not a skill file goes to the real curl untouched.
#
# It is installed before /harness/pre.sh runs, so a case that needs the fetch to
# fail can shadow it again.
# ---------------------------------------------------------------------------

script_version=$(sed -n 's/^SCRIPT_VERSION=//p' /harness/environment.sh | head -n 1)
command -v curl > /tmp/harness-real-curl
harness_raw_base=https://raw.githubusercontent.com/mattiasthalen/claude-cloud-environment
printf '%s\n' "${harness_raw_base}" > /tmp/harness-raw-base
printf '%s\n' "${harness_raw_base}/refs/tags/v${script_version}/skills" > /tmp/harness-skills-url

cat > /usr/local/bin/curl <<'SHIM'
#!/bin/bash
# Harness curl. Serves the working tree's skill sources for the tag-pinned URL
# and delegates everything else.
set -u

real_curl=$(cat /tmp/harness-real-curl)
skills_url=$(cat /tmp/harness-skills-url)
raw_base=$(cat /tmp/harness-raw-base)

url=""
dest=""
prev=""
for arg in "$@"; do
  case "${prev}" in
    -o | --output) dest="${arg}" ;;
  esac
  case "${arg}" in
    http*) [ -n "${url}" ] || url="${arg}" ;;
  esac
  prev="${arg}"
done

# Only this repo's own skill sources are intercepted. A skill file fetched from
# anywhere else is somebody else's business and goes to the real curl, so the
# shim cannot fail a step it was never meant to stand in for.
case "${url}" in
  "${skills_url}"/*) ;;
  "${raw_base}"/*/skills/*)
    echo "harness curl: refusing a skill URL that is not tag-pinned: ${url}" >&2
    exit 22
    ;;
  *) exec "${real_curl}" "$@" ;;
esac

skill_source="/harness/skills/${url#"${skills_url}"/}"
if [ ! -f "${skill_source}" ]; then
  echo "harness curl: no such skill source in the working tree: ${skill_source}" >&2
  exit 22
fi

if [ -n "${dest}" ]; then
  cp "${skill_source}" "${dest}"
else
  cat "${skill_source}"
fi
SHIM
chmod +x /usr/local/bin/curl

if [ -f /harness/pre.sh ]; then
  bash /harness/pre.sh
fi

bash /harness/environment.sh "$@" > /out/stdout 2> /out/stderr
status=$?
echo "${status}" > /out/status

# Collected container state. Add to this block when a case needs to assert on
# something else the script leaves behind.
if [ -f "${HOME}/.claude/settings.json" ]; then
  cp "${HOME}/.claude/settings.json" /out/settings.json
fi

if [ -f "${HOME}/.claude/CLAUDE.md" ]; then
  cp "${HOME}/.claude/CLAUDE.md" /out/CLAUDE.md
fi

# The plugin registry, which is the only place a plugin install records itself:
# a plugin whose manifest the CLI rejects leaves an enabling entry in
# settings.json and nothing here, so the two files together are what separate
# "installed" from "asked for".
if [ -f "${HOME}/.claude/plugins/installed_plugins.json" ]; then
  cp "${HOME}/.claude/plugins/installed_plugins.json" /out/installed-plugins.json
fi

# The dotfiles under ~/.claude, by name only. Some of what the script leaves
# there is a marker whose whole content is its existence — the caveman plugin's
# nudge suppressor is one — so the names are the state worth collecting, and
# copying the files would say no more.
: > /out/claude-dotfiles
for dotfile in "${HOME}"/.claude/.*; do
  [ -f "${dotfile}" ] || continue
  basename "${dotfile}" >> /out/claude-dotfiles
done

# Which of the tools this script installs ended up on PATH, one `NAME PATH` line
# each. Absence is a result too, so the file is written either way.
#
# The list is every selectable tool, and a tool missing from it makes
# assert_tool_on_path unpassable for that tool rather than merely unasserted —
# which is how newrelic and helm arrived with four cases that could not go green.
# Adding a tool to environment.sh means adding it here.
: > /out/tools
for tool in gcloud gke-gcloud-auth-plugin az kubectl snow prefect acli twg kubelogin newrelic helm git-lfs; do
  if resolved=$(command -v "${tool}"); then
    echo "${tool} ${resolved}" >> /out/tools
  fi
done

# Which skills the run installed, one `NAME PATH` line each. An empty file that
# the fetch left behind is not an installed skill, so size is part of the test.
: > /out/skills
for skill in "${HOME}"/.claude/skills/*/SKILL.md; do
  [ -s "${skill}" ] || continue
  name=$(basename "$(dirname "${skill}")")
  echo "${name} ${skill}" >> /out/skills
done

# The apt version of every installed package, one `NAME VERSION` line each. The
# binary on PATH does not say which repository it came from, and for kubectl
# that is the whole question: the Google Cloud repository publishes an
# epoch-versioned `kubectl` that is a different package at the same command.
dpkg-query -W -f '${Package} ${Version}\n' > /out/packages 2> /dev/null

# The system git config, which is where `git lfs install --system` registers the
# smudge/clean filters. It is read from /etc/gitconfig rather than from root's
# ~/.gitconfig deliberately: a session works as a different user, so a
# registration that landed in root's home would be invisible to it, and a case
# asserting on the system file is what catches that.
git config --system --list > /out/gitconfig-system 2> /dev/null ||
  : > /out/gitconfig-system

# An LFS round trip, so a case can assert on what the filters *do* rather than
# only on the config lines that claim they are installed. Committing writes a
# pointer through the clean filter; deleting the file and checking it back out
# restores the real bytes through the smudge filter, from this repo's own LFS
# store and with no server involved.
#
# Both halves are collected because either one alone passes for the wrong
# reason: with no filters registered git stores the real bytes verbatim, so the
# checked-out file looks right while nothing about LFS worked. Only a pointer in
# the commit and real bytes in the worktree means both filters ran.
: > /out/lfs-blob
: > /out/lfs-worktree
if command -v git-lfs > /dev/null 2>&1; then
  (
    set -e
    work=$(mktemp -d)
    cd "${work}"
    git init -q .
    git config user.email harness@example.invalid
    git config user.name harness
    git lfs track '*.bin' > /dev/null
    printf 'real-bytes-not-a-pointer' > payload.bin
    git add .gitattributes payload.bin
    git commit -qm payload
    git cat-file -p HEAD:payload.bin > /out/lfs-blob
    rm payload.bin
    git checkout -q -- payload.bin
    cp payload.bin /out/lfs-worktree
  ) > /dev/null 2>&1 || true
fi

# Everything above ran as root, and `cp` carries the source's mode across — so
# a file the script wrote for its own eyes only, as settings.json is, lands in
# /out unreadable to a host user who is not root. The host reads all of this.
chmod -R a+rX /out

# Always zero: a failing script is a result to report, not a harness error.
exit 0
