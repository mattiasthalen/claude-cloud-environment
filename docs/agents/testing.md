# Testing

## Running the suite

```sh
./tests/run.sh                      # every case
./tests/run.sh settings-json-shape  # named cases only
```

Requirements: a reachable Docker daemon, `jq` on the host, and network access to
`ubuntu:24.04`, `claude.ai` and the GitHub repositories the plugin steps clone.
That last one matches the `Full` network access level the environments already
run at. `tests/run.sh` exits `2` when it cannot run (no daemon, no `jq`, unknown
case name, image build failure), `1` when a case fails, `0` when all pass.

The first run builds `claude-cloud-environment-tests:base` from
`tests/base.Dockerfile` — Ubuntu 24.04 as root, pinned to `linux/amd64` because
every pin and install method in `environment.sh` assumes that base, and carrying
only what the hosted base image already provides before the script runs: a CA
store, `curl`, `git`, `jq` and the Claude Code CLI. Later runs reuse the image —
a cached rebuild costs a fraction of a second — and each case still gets a fresh
container from it.

Behind a TLS-intercepting proxy the harness passes `HTTPS_PROXY`/`HTTP_PROXY`/
`NO_PROXY` through to the build and the container, runs the container on the
host network so a loopback proxy is reachable, and installs the CA bundle named
by `SSL_CERT_FILE` or `CURL_CA_BUNDLE` into the image. With no proxy configured
none of that applies.

## What the tests are allowed to assert on

The seam is the one a real environment uses: invoke `environment.sh` with an
argument list in a fresh container and observe the result. Cases assert on the
script's **exit code**, on the **shape of its printed output**, and on the
**state it leaves in the container** — including installed binaries as reported
by the binaries themselves.

Cases do not assert on internal function names, accumulator contents, or the
order of lines within a phase. All three are free to change without the contract
changing.

`environment.sh` gets **no test-only flag, no dry-run mode and no extracted
helper library**. It is one file piped into `bash` by four environments, and a
test hook would be new surface on that line. A case that needs a different
starting state arranges it in the container with `harness_pre`.

## Adding a case

Add one file to `tests/cases/`; the runner picks it up by filename. The name is
what a failure reports, so name it after the behaviour.

```sh
#!/bin/bash
# One or two lines saying which behaviour this pins and why it matters.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run kubectl          # arbitrary argument list; none is valid too

assert_status 0
assert_first_line "environment.sh v$(harness_script_version)"
```

From `tests/lib.sh`:

| Helper | Use |
| --- | --- |
| `harness_run [args...]` | Run the script with that argument list in a fresh container. |
| `harness_pre <<'PRE' … PRE` | Snippet run in the container before the script, to arrange starting state. Call before `harness_run`. |
| `harness_script_version` | `SCRIPT_VERSION` read from the script, so a bump needs no case edits. |
| `harness_pin <VARIABLE>` | A pin read from the lockfile block, so a version roll needs no case edits. |
| `harness_pkg_version <package>` | The apt version dpkg reports for a package in the container, empty when it is not installed — the binary on PATH does not say which repository it came from. |
| `assert_status <code>` | Exit code. |
| `assert_first_line <line>` | First line of stdout. |
| `assert_output_contains <text>` | Fixed-string match over stdout and stderr. |
| `assert_output_lacks <text>` | The same match, negated — for asserting a phase did *not* run. |
| `assert_tool_on_path <binary>` | The binary is on PATH in the container after the run. |
| `assert_skill_installed <name>` | A non-empty `~/.claude/skills/<name>/SKILL.md` after the run. |
| `assert_skill_absent <name>` | The negation, for a run whose fetch was arranged to fail. |
| `assert_settings_jq <filter> <expected>` | Run a `jq` filter over the `settings.json` the run left behind; fails if it is missing or does not parse. |
| `harness_fail <message>` | Fail with a custom message. |

After `harness_run`, `HARNESS_STATUS`, `HARNESS_STDOUT`, `HARNESS_STDERR`,
`HARNESS_SETTINGS`, `HARNESS_TOOLS`, `HARNESS_SKILLS` and `HARNESS_PACKAGES` hold the raw result if a case needs something the assertions
above do not cover. Every assertion failure prints the case name, the
invocation, the exit code and the script's stdout and stderr.

To assert on some other container state, extend the collection block at the end
of `tests/container/run-case.sh` — that script runs inside the container, copies
what the run left behind into `/out`, and never asserts.

## The release-tag stand-in

`environment.sh` fetches the skills it ships from its own release tag, and a
working tree is by definition unreleased: the tag its `SCRIPT_VERSION` names
does not exist on GitHub while the change is being written, so that fetch could
only ever 404 in a container. `tests/container/run-case.sh` shadows `curl` with
a shim that stands in for the tag the release will cut, serving the working
tree's own `skills/` — mounted read-only at `/harness/skills` — for exactly the
tag-pinned URL and refusing any other URL for a skill file rather than passing
it to the network, where a branch ref would succeed. So a case that sees a skill
land has thereby seen the pinned URL. Everything that is not a skill file goes
to the real `curl`.

The shim is installed before `harness_pre` runs, so a case that needs the fetch
to fail shadows it again — `swarm-skill-fetch-failure-is-not-fatal` does.

Keep cases cheap. Failure-path cases are the cheap majority because validation
failures exit before any install work happens; expensive selections run once.
