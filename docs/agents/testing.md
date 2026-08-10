# Testing

## Not in a hosted web session

The container suite **does not run in a Claude Code on the web session**, and
that is settled rather than broken. Two things are in the way, and fixing the
first only exposes the second:

1. `/usr/bin/dockerd` is installed but no daemon is running, so the Docker
   socket does not exist. The session is uid 0, so starting it by hand works.
2. The session's egress policy then refuses Docker Hub — a `Forbidden` on
   `ubuntu:24.04` metadata, with the proxy answering `403` to `CONNECT` for
   `production.cloudfront.docker.com`. That is the blocker #43 hit, and #43
   closed by moving the suite into CI rather than by opening the allowlist.

So do not start the daemon and do not run `./tests/run.sh` there; both cost
minutes and end at the same wall. What gates a change written in such a session
is the host-side checks, which need no daemon and no network:

```sh
bash -n environment.sh          # the script still parses
./tests/tiers.test.sh           # every case declares a tier, and --tier selects right
./tests/check-version.test.sh   # SCRIPT_VERSION agrees with the tag it claims
```

The container suite itself is then covered by the `quick` tier on the pull
request, running on GitHub's runners where neither problem exists — that run is
the real gate. See the tier table below.

## Running the suite

On a host with Docker (a laptop, or a CI runner — not a hosted web session; see
above):

```sh
./tests/run.sh                      # every case
./tests/run.sh settings-json-shape  # named cases only
./tests/run.sh --tier quick         # one tier only
./tests/run.sh --tier quick --list  # the cases that tier selects, without running them
```

Requirements: a running Docker daemon the client can reach, `jq` on the host,
and network access to `ubuntu:24.04`, `claude.ai` and the GitHub repositories
the plugin steps clone. A hosted web session has neither the daemon nor the
Docker Hub access and cannot be given them.
That last one matches the `Full` network access level the environments already
run at. `tests/run.sh` exits `2` when it cannot run (no daemon, no `jq`, an argument it
cannot make sense of, a tier selection that would drop a case, image build
failure), `1` when a case fails, `0` when all pass.

The first run builds `claude-cloud-environment-tests:base` from
`tests/base.Dockerfile` — Ubuntu 24.04 as root, pinned to `linux/amd64` because
every pin and install method in `environment.sh` assumes that base, and carrying
only what the hosted base image already provides before the script runs: a CA
store, `curl`, `git`, `jq`, `uv` and the Claude Code CLI. `uv` is load-bearing
for two of `environment.sh`'s three install phases — the PyPI one runs through
it, and the release-archive one borrows it to unpack a zip — so a case that
exercises either is relying on the base image carrying it. Later runs reuse the image —
a cached rebuild costs a fraction of a second — and each case still gets a fresh
container from it.

Behind a TLS-intercepting proxy the harness passes `HTTPS_PROXY`/`HTTP_PROXY`/
`NO_PROXY` through to the build and the container, runs the container on the
host network so a loopback proxy is reachable, and installs the CA bundle named
by `SSL_CERT_FILE` or `CURL_CA_BUNDLE` into the image. With no proxy configured
none of that applies.

## Tiers, and which one gates a pull request

The suite is not uniformly cheap, so every case declares a tier in a `# tier:`
line and `--tier` selects on it.

| Tier | What is in it | Where it runs |
| --- | --- | --- |
| `quick` | Cases that install no CLI: validation failures, the collected-failure paths, the settings shape, the shipped skill. Seconds once the base image is built, and dependent on nothing beyond Docker Hub and `claude.ai`. | `.github/workflows/tests.yml`, on `pull_request` — **this is the tier that gates a PR**. |
| `vendor` | The selections that install real CLIs, so the run exercises the Microsoft, Google Cloud, Kubernetes, PyPI and Atlassian repositories. `az` alone is a 636 MB install and `gcloud` 883 MB. | `.github/workflows/tests-full.yml`, which runs the **whole** suite on a daily `schedule` and on `workflow_dispatch`. |

Because a hosted web session cannot run any container case at all, the `quick`
tier on the pull request is not merely the first gate such a change meets — it
is the only one that exercises the script in a container.

The split is about blast radius as much as cost: the vendor tier depends on five
external services staying up, and wiring it to `pull_request` would turn an
upstream hiccup into a red check on an unrelated change.

The tier lives in the case file rather than in a list inside a workflow, which
would drift the first time someone added a case. A case that declares no tier
belongs to no tier, so `--tier` refuses to select anything and exits `2` until
it is declared — a new case cannot silently run nowhere. An untiered run still
runs that case and says so on stderr: a missing comment line is a reason to
fail a tier selection, not a reason for the scheduled full suite to run nothing.
`tests/tiers.test.sh` checks the rule and the selection on the host, with no
Docker daemon needed, and the pull-request workflow runs it before the suite.

Both workflows call `scripts/run-tests-ci.sh`, one seam rather than two copies,
which turns the runner's exit `2` (the suite could not run at all) and exit `1`
(it ran and a case failed) into different annotations, because the two need
different fixes.

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
what a failure reports, so name it after the behaviour. Declare a tier — `quick`
if the case installs no CLI, `vendor` if it does; without one the runner refuses
to select any case at all.

```sh
#!/bin/bash
# One or two lines saying which behaviour this pins and why it matters.
# tier: quick
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
| `assert_claude_md_contains <text>` | Fixed-string match over the `~/.claude/CLAUDE.md` the run wrote; fails if the file is missing. |
| `harness_fail <message>` | Fail with a custom message. |

After `harness_run`, `HARNESS_STATUS`, `HARNESS_STDOUT`, `HARNESS_STDERR`,
`HARNESS_SETTINGS`, `HARNESS_CLAUDE_MD`, `HARNESS_TOOLS`, `HARNESS_SKILLS` and `HARNESS_PACKAGES` hold the raw result if a case needs something the assertions
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
