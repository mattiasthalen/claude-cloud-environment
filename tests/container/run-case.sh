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
#   /out/tools               the tools the run left on PATH
#   /out/skills              the skills the run left installed
#   /out/packages            the apt packages the container has
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
printf '%s\n' \
  "https://raw.githubusercontent.com/mattiasthalen/claude-cloud-environment/refs/tags/v${script_version}/skills" \
  > /tmp/harness-skills-url

cat > /usr/local/bin/curl <<'SHIM'
#!/bin/bash
# Harness curl. Serves the working tree's skill sources for the tag-pinned URL
# and delegates everything else.
set -u

real_curl=$(cat /tmp/harness-real-curl)
skills_url=$(cat /tmp/harness-skills-url)

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

case "${url}" in
  */SKILL.md) ;;
  *) exec "${real_curl}" "$@" ;;
esac

if [ "${url}" != "${skills_url}/${url##*/skills/}" ]; then
  echo "harness curl: refusing a skill URL that is not tag-pinned: ${url}" >&2
  exit 22
fi

skill_source="/harness/skills/${url##*/skills/}"
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

# Which of the tools this script installs ended up on PATH, one `NAME PATH` line
# each. Absence is a result too, so the file is written either way.
: > /out/tools
for tool in gcloud gke-gcloud-auth-plugin az kubectl snow acli; do
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

# Always zero: a failing script is a result to report, not a harness error.
exit 0
