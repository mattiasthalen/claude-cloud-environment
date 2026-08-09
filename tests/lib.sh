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
HARNESS_TOOLS=""
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
  HARNESS_TOOLS=""
  if [ -f "${out}/tools" ]; then
    HARNESS_TOOLS=$(cat "${out}/tools")
  fi
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
