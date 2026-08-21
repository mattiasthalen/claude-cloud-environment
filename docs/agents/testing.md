# Testing

## In a hosted web session

The container suite **does now run in a Claude Code on the web session**. This
section previously said it could not, on two grounds; the first is automated
away and the second no longer holds. That reverses issue #48, which closed by
forbidding exactly this automation — see
`docs/adr/0008-the-test-harness-starts-its-own-daemon.md` for why the reversal
is sound rather than an oversight.

1. `/usr/bin/dockerd` is installed but nothing starts it — PID 1 is the
   session's own supervisor, not an init system. `tests/run.sh` now starts the
   daemon itself when none answers and it has the rights to (see its comment at
   the daemon check). Nothing to do by hand.
2. Docker Hub is reachable. The old `403` on `ubuntu:24.04` metadata — the
   blocker #43 hit, and closed by moving the suite into CI rather than by
   opening the allowlist — does not reproduce. What appears instead is `429 Too
   Many Requests` on the anonymous pull limit, which clears on its own. It can
   sit there for tens of minutes, so retry with a backoff rather than
   concluding the run is blocked.

Two things about the environment are worth knowing before reading a failure as
a change of yours:

- **The daemon does not survive between commands.** It is reaped once the
  command that started it returns, even started under `setsid` with output
  redirected. `tests/run.sh` starting it per run is what makes this a non-issue;
  a daemon you started by hand in an earlier command will be gone.
- **Large downloads through the agent proxy get cut.** This is why
  `tests/base.Dockerfile` installs the CLI from npm rather than from
  `https://claude.ai/install.sh`, whose fetch of the native binary aborts three
  attempts running with "the connection dropped while downloading the update".
  `registry.npmjs.org` is in the proxy's no-proxy list and downloads direct.

The host-side checks still gate anything the container suite does not cover, and
need no daemon and no network:

```sh
bash -n environment.sh          # the script still parses
./tests/tiers.test.sh           # every case declares a tier, and --tier selects right
./tests/check-version.test.sh   # SCRIPT_VERSION agrees with the tag it claims
```

The pull request's `quick` tier run on GitHub's runners remains the real gate —
a local pass in a hosted session is a faster signal, not a replacement. See the
tier table below.

## Running the suite

On any host with Docker installed — a laptop, a CI runner, or a hosted web
session (see above):

```sh
./tests/run.sh                      # every case
./tests/run.sh settings-json-shape  # named cases only
./tests/run.sh --tier quick         # one tier only
./tests/run.sh --tier quick --list  # the cases that tier selects, without running them
```

Requirements: Docker, `jq` on the host, and network access to `ubuntu:24.04`,
`registry.npmjs.org` and the GitHub repositories the plugin steps clone. The
daemon need not already be running — `tests/run.sh` starts one where it can.
That last one matches the `Full` network access level the environments already
run at. `tests/run.sh` exits `2` when it cannot run (no daemon, no `jq`, an argument it
cannot make sense of, a tier selection that would drop a case, image build
failure), `1` when a case fails, `0` when all pass.

The first run builds `claude-cloud-environment-tests:base` from
`tests/base.Dockerfile` — Ubuntu 24.04 as root, pinned to `linux/amd64` because
every pin and install method in `environment.sh` assumes that base, and carrying
close to what the hosted base image already provides before the script runs: a
CA store, `curl`, `git`, `jq`, `uv` and the Claude Code CLI. It carries one
thing the hosted image does not — a Node runtime, because the CLI is installed
from npm rather than by `https://claude.ai/install.sh`, whose fetch of the
native binary is cut off partway behind a TLS-intercepting proxy. What a case
needs is a `claude` on PATH, and which packaging put it there is not something
`environment.sh` can observe; nothing in this repo installs or asserts Node, so
no case can mistake it for provisioning. The CLI is pinned, and the pin is
asserted after install like every pin in `environment.sh`; bump it at the
`CLAUDE_CODE_VERSION` argument in `tests/base.Dockerfile`. `uv` is load-bearing
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
| `quick` | Cases that install no CLI: validation failures, the collected-failure paths, the settings shape, the shipped skill. Seconds once the base image is built, and dependent on nothing beyond Docker Hub and `registry.npmjs.org`. | `.github/workflows/tests.yml`, on `pull_request` — **this is the tier that gates a PR**. |
| `vendor` | The selections that install real CLIs, so the run exercises the Microsoft, Google Cloud, Kubernetes and PyPI repositories, plus a handful of vendors' own download hosts. `az` alone is a 636 MB install and `gcloud` 883 MB. | `.github/workflows/tests-full.yml`, which runs the **whole** suite on a daily `schedule` and on `workflow_dispatch`. |

The `quick` tier on the pull request is the gate a change written in a hosted
session must clear, whether or not the author also ran it locally: a local run
sits behind an anonymous Docker Hub limit and a proxy that cuts large downloads,
so it can be unavailable for reasons that have nothing to do with the change.

The split is about blast radius as much as cost: the vendor tier depends on
several external services staying up, and wiring it to `pull_request` would
turn an upstream hiccup into a red check on an unrelated change.

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
| `assert_no_steps_ran` | No step announcement (`==> `) appears in the output — for a case whose whole point is that validation fails before any step is attempted. |
| `assert_tool_on_path <binary>` | The binary is on PATH in the container after the run. |
| `assert_skill_installed <name>` | A non-empty `~/.claude/skills/<name>/SKILL.md` after the run. |
| `assert_skill_absent <name>` | The negation, for a run whose fetch was arranged to fail. |
| `assert_settings_jq <filter> <expected>` | Run a `jq` filter over the `settings.json` the run left behind; fails if it is missing or does not parse. |
| `assert_claude_md_contains <text>` | Fixed-string match over the `~/.claude/CLAUDE.md` the run wrote; fails if the file is missing. |
| `assert_claude_dotfile <name>` | A dotfile of that exact name directly under `~/.claude` after the run — for markers whose existence is their whole content. |
| `assert_plugin_installed <plugin@marketplace>` | The plugin is in the CLI's own registry after the run — the claim `enabledPlugins` in `settings.json` cannot make, because that entry is written whether or not the install succeeded. |
| `harness_fail <message>` | Fail with a custom message. |

After `harness_run`, `HARNESS_STATUS`, `HARNESS_STDOUT`, `HARNESS_STDERR`,
`HARNESS_SETTINGS`, `HARNESS_CLAUDE_MD`, `HARNESS_CLAUDE_DOTFILES`,
`HARNESS_INSTALLED_PLUGINS`, `HARNESS_TOOLS`, `HARNESS_SKILLS` and
`HARNESS_PACKAGES` hold the raw result if a case needs something the assertions
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
