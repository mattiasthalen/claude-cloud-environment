# Harness library. Sourced by tests/run.sh and by every case in tests/cases/.
#
# The seam is the one a real environment uses: invoke environment.sh with an
# argument list in a fresh Ubuntu 24.04 x86_64 root container and assert on what
# it exits with, what it prints, and what it leaves in the container. The script
# gets no test-only flag, no dry-run mode and no extracted helper library — a
# case that needs a different starting state arranges it in the container with
# harness_pre, not in the script.

set -uo pipefail

HARNESS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${HARNESS_DIR}/.." && pwd)
HARNESS_IMAGE=claude-cloud-environment-tests:base

# Populated by harness_run.
HARNESS_STATUS=""
HARNESS_STDOUT=""
HARNESS_STDERR=""
HARNESS_SETTINGS=""
HARNESS_CLAUDE_MD=""
HARNESS_TOOLS=""
HARNESS_SKILLS=""
HARNESS_PACKAGES=""
HARNESS_GITCONFIG_SYSTEM=""
HARNESS_LFS_BLOB=""
HARNESS_LFS_WORKTREE=""
HARNESS_ARGS_DESC=""
_harness_pre_file=""

# ---------------------------------------------------------------------------
# Docker plumbing
# ---------------------------------------------------------------------------

# Proxy and CA passthrough, for a machine whose outbound HTTPS goes through a
# TLS-intercepting proxy on the loopback interface. Without a proxy configured
# this adds nothing and the container uses the default bridge network.
_harness_ca_bundle() {
  local candidate
  for candidate in "${SSL_CERT_FILE:-}" "${CURL_CA_BUNDLE:-}"; do
    if [ -n "${candidate}" ] && [ -f "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

_harness_proxy_configured() {
  [ -n "${HTTPS_PROXY:-}${https_proxy:-}${HTTP_PROXY:-}${http_proxy:-}" ]
}

_harness_proxy_run_args() {
  _harness_proxy_configured || return 0
  # Loopback proxies are not reachable from a bridged container.
  printf '%s\n' --network host \
    -e HTTPS_PROXY -e HTTP_PROXY -e NO_PROXY \
    -e https_proxy -e http_proxy -e no_proxy
}

# Builds the base image if it is missing or its Dockerfile changed. A cached
# rebuild costs a fraction of a second, so this runs unconditionally.
harness_build_image() {
  local context ca build_args=(--platform linux/amd64)
  context=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '${context}'" RETURN

  cp "${HARNESS_DIR}/base.Dockerfile" "${context}/Dockerfile"
  mkdir -p "${context}/ca"
  if ca=$(_harness_ca_bundle); then
    cp "${ca}" "${context}/ca/harness-proxy.crt"
  fi
  if _harness_proxy_configured; then
    build_args+=(--network host
      --build-arg HTTPS_PROXY --build-arg HTTP_PROXY --build-arg NO_PROXY
      --build-arg https_proxy --build-arg http_proxy --build-arg no_proxy)
  fi

  echo "==> building ${HARNESS_IMAGE}"
  if ! docker build "${build_args[@]}" -t "${HARNESS_IMAGE}" "${context}"; then
    echo "harness: failed to build ${HARNESS_IMAGE}" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Case API
# ---------------------------------------------------------------------------

# harness_pre <<'EOF' ... EOF
# Registers a snippet to run in the container before the script. Use it to
# arrange the starting state a case needs — shadowing a binary, pre-creating a
# file. One snippet per case; call before harness_run.
harness_pre() {
  _harness_pre_file=$(mktemp)
  cat > "${_harness_pre_file}"
}

# harness_run [args...]
# Runs environment.sh with the given argument list in a fresh container, then
# fills HARNESS_STATUS, HARNESS_STDOUT, HARNESS_STDERR and HARNESS_SETTINGS.
harness_run() {
  local out mounts=() proxy_args=()
  out=$(mktemp -d)

  mounts=(
    -v "${REPO_ROOT}/environment.sh:/harness/environment.sh:ro"
    -v "${REPO_ROOT}/skills:/harness/skills:ro"
    -v "${HARNESS_DIR}/container/run-case.sh:/harness/run-case.sh:ro"
    -v "${out}:/out"
  )
  if [ -n "${_harness_pre_file}" ]; then
    mounts+=(-v "${_harness_pre_file}:/harness/pre.sh:ro")
  fi
  mapfile -t proxy_args < <(_harness_proxy_run_args)

  HARNESS_ARGS_DESC="environment.sh${*:+ $*}"
  if ! docker run --rm --platform linux/amd64 "${mounts[@]}" ${proxy_args[@]+"${proxy_args[@]}"} \
    "${HARNESS_IMAGE}" /harness/run-case.sh "$@" > "${out}/docker.log" 2>&1; then
    HARNESS_STDERR=$(cat "${out}/docker.log")
    harness_fail "docker run failed before the script produced a result"
  fi

  HARNESS_STATUS=$(cat "${out}/status")
  HARNESS_STDOUT=$(cat "${out}/stdout")
  HARNESS_STDERR=$(cat "${out}/stderr")
  HARNESS_SETTINGS=""
  if [ -f "${out}/settings.json" ]; then
    HARNESS_SETTINGS=$(cat "${out}/settings.json")
  fi
  HARNESS_CLAUDE_MD=""
  if [ -f "${out}/CLAUDE.md" ]; then
    HARNESS_CLAUDE_MD=$(cat "${out}/CLAUDE.md")
  fi
  HARNESS_CLAUDE_DOTFILES=""
  if [ -f "${out}/claude-dotfiles" ]; then
    HARNESS_CLAUDE_DOTFILES=$(cat "${out}/claude-dotfiles")
  fi
  HARNESS_TOOLS=""
  if [ -f "${out}/tools" ]; then
    HARNESS_TOOLS=$(cat "${out}/tools")
  fi
  HARNESS_SKILLS=""
  if [ -f "${out}/skills" ]; then
    HARNESS_SKILLS=$(cat "${out}/skills")
  fi
  HARNESS_PACKAGES=""
  if [ -f "${out}/packages" ]; then
    HARNESS_PACKAGES=$(cat "${out}/packages")
  fi
  HARNESS_GITCONFIG_SYSTEM=""
  if [ -f "${out}/gitconfig-system" ]; then
    HARNESS_GITCONFIG_SYSTEM=$(cat "${out}/gitconfig-system")
  fi
  HARNESS_LFS_BLOB=""
  if [ -f "${out}/lfs-blob" ]; then
    HARNESS_LFS_BLOB=$(cat "${out}/lfs-blob")
  fi
  HARNESS_LFS_WORKTREE=""
  if [ -f "${out}/lfs-worktree" ]; then
    HARNESS_LFS_WORKTREE=$(cat "${out}/lfs-worktree")
  fi
}

# harness_pkg_version <package>
# The apt version of a package as the container's own dpkg database reports it,
# empty when the package is not installed. The binary on PATH does not say which
# repository it came from; this does.
harness_pkg_version() {
  printf '%s\n' "${HARNESS_PACKAGES}" | sed -n "s/^$1 //p" | head -n 1
}

# The version the script under test reports, read from the script itself so a
# bump does not need a matching edit in every case.
harness_script_version() {
  local version
  version=$(sed -n 's/^SCRIPT_VERSION=\(.*\)$/\1/p' "${REPO_ROOT}/environment.sh" | head -n 1)
  if [ -z "${version}" ]; then
    harness_fail "could not read SCRIPT_VERSION from environment.sh"
  fi
  printf '%s' "${version}"
}

# harness_pin <VARIABLE>
# A pin read from the lockfile block of the script under test, so a version roll
# is one diff hunk there rather than an edit in every case that names a version.
harness_pin() {
  local name=$1 value
  value=$(sed -n "s/^${name}=\(.*\)$/\1/p" "${REPO_ROOT}/environment.sh" | head -n 1)
  if [ -z "${value}" ]; then
    harness_fail "could not read ${name} from the lockfile block of environment.sh"
  fi
  printf '%s' "${value}"
}

# ---------------------------------------------------------------------------
# Assertions. Each prints what it expected, what it got, and the script output
# that produced it, then ends the case.
# ---------------------------------------------------------------------------

harness_fail() {
  echo "ASSERTION FAILED: $1" >&2
  echo >&2
  echo "  invocation: ${HARNESS_ARGS_DESC:-<none>}" >&2
  echo "  exit code : ${HARNESS_STATUS:-<none>}" >&2
  echo >&2
  echo "--- script stdout ---" >&2
  printf '%s\n' "${HARNESS_STDOUT}" >&2
  echo "--- script stderr ---" >&2
  printf '%s\n' "${HARNESS_STDERR}" >&2
  echo "---------------------" >&2
  exit 1
}

assert_status() {
  local expected=$1
  [ "${HARNESS_STATUS}" = "${expected}" ] ||
    harness_fail "expected exit code ${expected}, got ${HARNESS_STATUS}"
}

assert_first_line() {
  local expected=$1 actual
  actual=$(printf '%s\n' "${HARNESS_STDOUT}" | head -n 1)
  [ "${actual}" = "${expected}" ] ||
    harness_fail "expected first line of output '${expected}', got '${actual}'"
}

assert_output_contains() {
  local needle=$1
  printf '%s\n%s\n' "${HARNESS_STDOUT}" "${HARNESS_STDERR}" | grep -qF -- "${needle}" ||
    harness_fail "expected output to contain '${needle}'"
}

assert_output_lacks() {
  local needle=$1
  printf '%s\n%s\n' "${HARNESS_STDOUT}" "${HARNESS_STDERR}" | grep -qF -- "${needle}" &&
    harness_fail "expected output not to contain '${needle}'"
  return 0
}

# assert_tool_on_path <binary>
# The binary the run left on PATH, as the container reports it — presence proves
# a file landed, which is a different claim from the script's own verification
# line saying the tool ran.
assert_tool_on_path() {
  local tool=$1
  printf '%s\n' "${HARNESS_TOOLS}" | grep -q "^${tool} " ||
    harness_fail "expected '${tool}' on PATH after the run, found: ${HARNESS_TOOLS:-<none>}"
}

# assert_skill_installed <name>
# A non-empty SKILL.md the run left under ~/.claude/skills/<name>/. Presence in
# the container is a different claim from the script's own verification row, and
# it is only reachable through the tag-pinned URL — the harness curl refuses any
# other (see tests/container/run-case.sh).
assert_skill_installed() {
  local skill=$1
  printf '%s\n' "${HARNESS_SKILLS}" | grep -q "^${skill} " ||
    harness_fail "expected the skill '${skill}' installed after the run, found: ${HARNESS_SKILLS:-<none>}"
}

# assert_skill_absent <name>
# The negation, for a run whose fetch was arranged to fail.
assert_skill_absent() {
  local skill=$1
  printf '%s\n' "${HARNESS_SKILLS}" | grep -q "^${skill} " &&
    harness_fail "expected no '${skill}' skill after the run, found: ${HARNESS_SKILLS}"
  return 0
}

# assert_system_git_config <key>
# A key with a non-empty value in the container's /etc/gitconfig after the run.
# The system file is the assertion on purpose: this script runs as root and a
# session runs as another user, so a setting that reached only root's own
# ~/.gitconfig would pass a laxer check and still do nothing for a session.
assert_system_git_config() {
  local key=$1
  printf '%s\n' "${HARNESS_GITCONFIG_SYSTEM}" | grep -q "^${key}=." ||
    harness_fail "expected /etc/gitconfig to set '${key}' after the run, found: ${HARNESS_GITCONFIG_SYSTEM:-<none>}"
}

# assert_system_git_config_lacks <key>
# The negation, for a run that was arranged to leave the filters unregistered.
assert_system_git_config_lacks() {
  local key=$1
  printf '%s\n' "${HARNESS_GITCONFIG_SYSTEM}" | grep -q "^${key}=" &&
    harness_fail "expected /etc/gitconfig not to set '${key}' after the run, found: ${HARNESS_GITCONFIG_SYSTEM}"
  return 0
}

# assert_lfs_round_trip
# The LFS filters did what they exist to do, asserted on the round trip the
# container performed after the run (see tests/container/run-case.sh): the
# committed blob is a pointer, so the clean filter ran, and the checked-out file
# is the real payload, so the smudge filter ran. Asserting only the second half
# would pass on a container with no filters at all, where git stores and returns
# the same real bytes and nothing about LFS happened.
assert_lfs_round_trip() {
  printf '%s\n' "${HARNESS_LFS_BLOB}" | grep -q '^version https://git-lfs' ||
    harness_fail "expected the committed blob to be an LFS pointer, got: ${HARNESS_LFS_BLOB:-<none>}"
  [ "${HARNESS_LFS_WORKTREE}" = "real-bytes-not-a-pointer" ] ||
    harness_fail "expected the checked-out file to carry the real bytes, got: ${HARNESS_LFS_WORKTREE:-<none>}"
}

# assert_claude_md_contains <substring>
# A line of the memory file the run wrote to ~/.claude/CLAUDE.md. Fails if the
# file is missing, so a run that skipped the write is not a silent pass.
assert_claude_md_contains() {
  local needle=$1
  [ -n "${HARNESS_CLAUDE_MD}" ] ||
    harness_fail "expected the run to leave a non-empty ~/.claude/CLAUDE.md, found none"
  printf '%s\n' "${HARNESS_CLAUDE_MD}" | grep -qF -- "${needle}" ||
    harness_fail "expected ~/.claude/CLAUDE.md to contain '${needle}', got: ${HARNESS_CLAUDE_MD}"
}

# assert_claude_dotfile <name>
# A dotfile the run left directly under ~/.claude, named exactly. For markers
# whose existence is their whole content.
assert_claude_dotfile() {
  local name=$1
  printf '%s\n' "${HARNESS_CLAUDE_DOTFILES}" | grep -qx -- "${name}" ||
    harness_fail "expected ~/.claude/${name} after the run, found: ${HARNESS_CLAUDE_DOTFILES:-<none>}"
}

# assert_settings_jq <jq-filter> <expected-output>
# Runs the filter over the settings.json the run left behind. Fails if the file
# is missing or does not parse.
assert_settings_jq() {
  local filter=$1 expected=$2 actual
  [ -n "${HARNESS_SETTINGS}" ] ||
    harness_fail "expected the run to leave a settings.json, found none"
  actual=$(printf '%s' "${HARNESS_SETTINGS}" | jq -r "${filter}" 2>&1) ||
    harness_fail "settings.json did not parse as JSON: ${actual}"
  [ "${actual}" = "${expected}" ] ||
    harness_fail "expected settings.json ${filter} to be '${expected}', got '${actual}'"
}
