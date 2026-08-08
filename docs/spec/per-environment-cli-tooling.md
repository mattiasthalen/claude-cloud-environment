# Spec: per-environment CLI tooling in `environment.sh`

Status: accepted, not yet implemented.
Source: the wayfinder map in [issue #10](https://github.com/mattiasthalen/claude-cloud-environment/issues/10) and its ten resolved tickets, linked per section.

This spec describes how `environment.sh` installs a per-environment selection of
client CLIs. It is written to be implemented mechanically: every command, pin,
failure rule and output line below is decided, not proposed.

## 1. Context and prerequisites

`environment.sh` is the setup script for Claude Code on the web environments.
Four environments each paste a one-line setup-script box that pipes this
repository's `environment.sh` into `bash`. Each environment needs a different
subset of CLIs: `gcloud`, `az`, `kubectl`, `snow`, `acli`, plus add-ons.

Fixed facts the spec relies on:

- **Container**: Ubuntu 24.04 (noble), x86_64, running as **root**. `apt-get`,
  `curl`, `jq`, `git`, `python3`, `pip`, `uv`, `node`/`npm` are present. There is
  no `gh` and no `pipx`. Roughly 30 GB writable.
- **Network access level is `Full` on all four environments.** This is a stated
  prerequisite, not something the script checks or influences: there is no host
  allowlist, no host table, and no preflight reachability check
  ([#19](https://github.com/mattiasthalen/claude-cloud-environment/issues/19)).
- **The environment-variables configuration is applied after the setup script
  runs**, so the script cannot read it. Selection must be inline in the box.
- **`environment.sh` stays a single file.** A piped script could `curl` sibling
  files at runtime, but that trades one atomic fetch for N fetches that can
  half-fail mid-run.
- **The setup script must exit zero** or the session does not start, and it has
  roughly a five-minute budget. Container snapshots are cached, so install cost
  is paid on rebuild only; the snapshot expires after about seven days and also
  rebuilds when the box text or the allowed hosts change. Pushing to this
  repository invalidates nothing.
- **No credentials, ever.** This script installs binaries. Authentication and
  client-specific configuration are handled by each environment's own box.
- **No client names** appear in this repository. Tool names are fine.
- Replacing the base image is not an option on Anthropic-hosted environments, so
  the setup script is the right layer for this work
  ([#13](https://github.com/mattiasthalen/claude-cloud-environment/issues/13)).

## 2. Selection transport and the setup-script box

Selection rides on **positional arguments through the pipe**
([#11](https://github.com/mattiasthalen/claude-cloud-environment/issues/11)).
`bash -s` reads the script from stdin and treats everything after `--` as
positional parameters, so the script sees the requested tools in `"$@"`.

The line an environment pastes into its setup-script box:

```
curl -sL https://raw.githubusercontent.com/mattiasthalen/claude-cloud-environment/refs/tags/v1.0.0/environment.sh | bash -s -- gcloud kubectl snow
```

- The ref is an **immutable semver tag**, never `refs/heads/main`
  ([#19](https://github.com/mattiasthalen/claude-cloud-environment/issues/19),
  [#22](https://github.com/mattiasthalen/claude-cloud-environment/issues/22)).
  See section 8.
- **Tool names are binary names**: `gcloud`, `az`, `kubectl`, `snow`, `acli`,
  `gke-gcloud-auth-plugin`. The name typed in the box is the name typed in the
  terminal. Product names (`snowflake`, `azure`) are not accepted as aliases;
  there is no synonym table.
- **Zero arguments is valid.** The plugin and settings work still runs. This is
  today's invocation, so no environment has to change until it wants a tool.
- **Unknown names are fatal**, validated before any install runs (section 5).

Release assets were rejected as the carrier: a setup script fetching them from
an unattached repository gets a 403.

## 3. The tool table

One row per installable thing — a **flat namespace**. There is no "add-on"
concept in the script: an add-on is a tool name whose installer happens to be an
apt package with a longer name
([#20](https://github.com/mattiasthalen/claude-cloud-environment/issues/20)).

| Argument | Installer | Package / distribution | Pin | Parent | Verify with | Expected |
| --- | --- | --- | --- | --- | --- | --- |
| `gcloud` | apt (Google Cloud repo) | `google-cloud-cli` | `=${GCLOUD_VERSION}` | — | `gcloud version` | `${GCLOUD_VERSION%%-*}` |
| `az` | apt (Microsoft repo) | `azure-cli` | `=${AZ_VERSION}` | — | `az version` | `${AZ_VERSION%%-*}` |
| `kubectl` | apt (`pkgs.k8s.io` repo) | `kubectl` | `=${KUBECTL_VERSION}` | — | `kubectl version --client` | `v${KUBECTL_VERSION%%-*}` |
| `snow` | `uv tool install` | `snowflake-cli` | `==${SNOW_VERSION}` | — | `snow --version` | `${SNOW_VERSION}` |
| `acli` | apt (Atlassian repo) | `acli` | none — unpinnable | — | `acli --version` | none — not asserted |
| `gke-gcloud-auth-plugin` | apt (Google Cloud repo) | `google-cloud-cli-gke-gcloud-auth-plugin` | `=${GCLOUD_VERSION}` | `gcloud` | `gke-gcloud-auth-plugin --version` | none — invocability only |

Measured install cost for the full five-tool set: **~53 s and ~1.74 GB**
(`gcloud` 883 MB, `az` 636 MB, `kubectl` 58 MB, `snow` 147 MB, `acli` 16 MB).
That is comfortably inside the five-minute budget and the ~30 GB of writable
space, so install cost constrains nothing
([#12](https://github.com/mattiasthalen/claude-cloud-environment/issues/12), all
figures measured in an Ubuntu 24.04.4 x86_64 container as root; see
`docs/research/cli-install-methods.md`).

Rows are added **on demand**. The Google Cloud repository carries 40
`google-cloud-cli-*` component packages; enumerating them would multiply the
pinning obligation across a catalogue nobody has asked for.
`gke-gcloud-auth-plugin` ships from day one because the in-tree GKE auth
provider was removed in Kubernetes 1.26, so `kubectl` against GKE does not work
without it.

## 4. Install method per tool

### Lockfile block

One declarative block at the top of the file, read as a lockfile. Nothing else
in the script hard-codes a version
([#15](https://github.com/mattiasthalen/claude-cloud-environment/issues/15)):

```sh
GCLOUD_VERSION=579.0.0-0
AZ_VERSION=2.89.0-1~noble
KUBECTL_MINOR=1.34
KUBECTL_VERSION=1.34.10-1.1
SNOW_VERSION=3.16.0
# acli: deliberately unpinned — upstream offers no pin
```

`KUBECTL_MINOR` and `KUBECTL_VERSION` are two explicit variables, not one with
the other derived by string manipulation: the `pkgs.k8s.io` repository URL
embeds the minor version, and explicit beats slicing in bash. If the two drift
apart the pinned version will not exist in the configured repository and the
hard fail (section 5) fires immediately.

### Repository setup

Each unique repository is set up **once**, guarded so a second tool from the
same vendor is a no-op. All keyring fetches are HTTPS; `ca-certificates`,
`curl` and `gnupg` are already present, so the vendors' "install prerequisites"
step is a no-op here. `sudo` is never needed.

Google Cloud (`gcloud`, `gke-gcloud-auth-plugin`):

```bash
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  > /etc/apt/sources.list.d/google-cloud-sdk.list
```

Microsoft (`az`) — a deb822 `.sources` file, not a one-line `.list` entry:

```bash
mkdir -p /etc/apt/keyrings
curl -sLS https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor > /etc/apt/keyrings/microsoft.gpg
chmod go+r /etc/apt/keyrings/microsoft.gpg
cat > /etc/apt/sources.list.d/azure-cli.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: noble
Components: main
Architectures: amd64
Signed-by: /etc/apt/keyrings/microsoft.gpg
EOF
```

Kubernetes (`kubectl`) — the minor version appears in the URL:

```bash
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBECTL_MINOR}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBECTL_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list
```

Atlassian (`acli`):

```bash
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://acli.atlassian.com/gpg/public-key.asc \
  | gpg --dearmor -o /etc/apt/keyrings/acli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/acli-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/acli-archive-keyring.gpg] https://acli.atlassian.com/linux/deb stable main" \
  > /etc/apt/sources.list.d/acli.list
```

### One update, one install

```bash
apt-get update
apt-get install -y "${apt_pkgs[@]}"
```

`-y` is mandatory on every apt install; `DEBIAN_FRONTEND=noninteractive` is
cheap belt-and-braces. A single combined `apt-get update` across all four
vendor repositories takes about two seconds regardless of how many tools were
selected.

**Every package is pinned explicitly, including add-ons.**
`google-cloud-cli-gke-gcloud-auth-plugin` declares no `Depends` and the base
package only `Suggests:` its components, so apt will not match versions on its
own:

```bash
apt-get install -y google-cloud-cli=579.0.0-0 google-cloud-cli-gke-gcloud-auth-plugin=579.0.0-0
```

**The `kubectl` pin is mandatory, not hygienic.** The Google Cloud repository
publishes its own `kubectl` at epoch `1:579.0.0-0`, which outranks anything from
`pkgs.k8s.io`. With both repositories enabled, a plain `apt-get install kubectl`
silently installs Google's build. Reproduced: `apt-get install -s kubectl`
resolves to `Inst kubectl (1:579.0.0-0 cloud-sdk:cloud-sdk [amd64])`.

### Non-apt installs

`snow` only:

```bash
UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 "snowflake-cli==${SNOW_VERSION}"
```

`UV_TOOL_BIN_DIR` puts the shim somewhere unambiguously on `PATH` (`uv` defaults
to `~/.local/bin`, which a non-login shell may not have). `--python 3.12` makes
the interpreter choice explicit rather than inheriting `uv`'s pick; Snowflake
requires 3.10+.

### `az` extensions

In scope by the same rules, installed with `az extension add --system`, which
writes to the Python lib system dir rather than binding the install to root's
`$HOME`. `--version <v>` pins exactly and fails loudly on a bad version;
`--source <wheel-url>` is an alternative pin; `-y` suppresses prompts; re-adding
an already-present extension warns and exits 0. **No extension row ships
today** — same on-demand rule as gcloud components.

## 5. Failure and idempotency policy

([#14](https://github.com/mattiasthalen/claude-cloud-environment/issues/14))

1. **`|| true` is removed from the script entirely.** A failed install is fatal:
   the script exits non-zero and the session does not start. A container that
   cannot be built should not be handed to a session. Printed output is the only
   failure signal — no marker file, no `CLAUDE.md` line, because there is no
   session to read it.
2. **Idempotency comes from a guard, not a swallowed exit code.** Each install is
   preceded by a `command -v <binary>` guard and skipped when the binary is
   already present. The guard is **presence-only**: it does not compare versions
   and does not reinstall at the pin. A wrong version is caught by verification
   (section 6), where the remedy is a rebuild.
3. **Collect failures, fail once at the end.** Every install is attempted;
   failures accumulate in one array; the script exits `1` once at the end rather
   than aborting on the first. A rebuild cycle is expensive, so an
   abort-fix-rebuild round trip per broken tool is the wrong trade. It also keeps
   backgrounded parallel installs viable if the five-minute budget ever bites.
4. **One policy, no tiers.** The plugin and settings block is as fatal as the CLI
   installs. Two failure policies in one file was rejected.
5. **Arguments are validated before any install runs.** An unrecognised name
   fails immediately with an error naming the valid set. Requesting an add-on
   **without its parent** is the same class of fatal validation error — measured,
   a lone add-on install does not drag in an unpinned parent, it installs a
   plugin with nothing to plug into.
6. **A dead pin is a hard fail, never a fallback to latest.** When
   `apt-get install <pkg>=<pin>` finds no such version, the script fails through
   the collected-failure path. The message names the tool and the dead pin. The
   cost is understood and accepted: a dead pin blocks all four environments until
   the pin is bumped in `main`.
7. **`acli` is the one unpinned tool**, by upstream necessity, and its version is
   **not asserted**. An assertion would turn every upstream `acli` release into a
   session-blocking failure — a worse trade than accepting drift on a tool that is
   16 MB and 2 s.
8. **Output streams; the recap names failed steps only.** Setup output is visible
   in the container-start checklist, so the real error text stays where it occurs.
   The end-of-run recap exists to make the cause findable at the bottom, not to
   reproduce it. The exit code is a plain `1`.
9. **`claude plugin enable` is dropped.** Measured in-container: `marketplace add`
   and `install` are both idempotent (exit 0 when already present); only `enable`
   is not (exit 1, "already enabled"). Instead of guarding it, the `jq` settings
   block sets the state directly:

   ```
   .enabledPlugins["mattpocock-skills@mattpocock"] = true
   ```

   `claude plugin disable` writes `false` rather than deleting the key, so the
   assignment must set `true` explicitly — a merge that only adds missing keys
   would not re-enable a deliberately disabled plugin. `claude plugin marketplace
   add` stays a command, because `install` requires the marketplace to be
   registered at install time and `settings.json` is written last.

## 6. Verification

([#16](https://github.com/mattiasthalen/claude-cloud-environment/issues/16))

Verification is the **last block in the script** and a **second, independent
gate**. Installers stay fatal so their error text appears where it occurs;
verification catches the case where an installer exits zero but leaves a
non-runnable binary (a quietly failing post-install script, `uv tool install`
linking the wrong Python).

- **Every requested tool is invoked**, not merely located: `gcloud version`,
  `az version`, `kubectl version --client`, `snow --version`, `acli --version`.
  Presence proves a file landed; invocation proves the tool can start. Cost is
  ~5-8 s for the full set.
- **The printed version is asserted against the pin, and a mismatch is fatal.**
  The expected string is derived from the lockfile by stripping the packaging
  suffix (`${GCLOUD_VERSION%%-*}`, `${AZ_VERSION%%-*}`), keeping one source of
  truth per tool. A separate `*_EXPECTED` variable was rejected as duplication
  that can drift; containment matching was rejected as too loose (`1.3` is
  contained in `1.34.10-1.1`). Extraction from each tool's *output* is per-tool
  regardless — `kubectl` prefixes a `v`, `snow` prints a sentence, `az` prints a
  block.
- **`acli` is invoked but not asserted.** Add-on rows likewise assert
  **invocability only** — exit zero and non-empty output — because
  `gke-gcloud-auth-plugin --version` prints a Kubernetes client version, not the
  apt pin. Which build landed is already guaranteed by the pin.
- **Scope is the requested tools only**, plus a `settings.json` read-back. No
  "not requested" rows. When no CLIs were requested — a valid invocation — the
  block still runs, performs the read-back, and prints the empty case explicitly,
  so a deliberate empty selection and a mangled argument line do not look
  identical in the log.
- **The `settings.json` read-back** asserts the file parses as JSON and carries
  the expected keys: the `enabledPlugins` entries and `permissions.defaultMode`.
  `claude plugin list` is deliberately not consulted — its output format is not a
  contract, and `enabledPlugins` *is* the mechanism.
- **A tool whose install already failed is not re-verified.** Verification checks
  membership in the failure array first and skips; the install failure is the more
  informative entry.
- **Verification failures append to the same failure array** as install failures.
  One list, one recap, one `exit 1`.

Output format — one line per tool, the pin shown only on failure:

```
✓ gcloud 579.0.0
✓ kubectl v1.34.10
✗ snow 3.15.1, expected 3.16.0
```

Silence on success was rejected: a block that prints nothing when everything
works gives no way to tell it ran.

## 7. File layout

([#17](https://github.com/mattiasthalen/claude-cloud-environment/issues/17))

`environment.sh` is a **phased pipeline**, not a per-tool installer that runs
end-to-end for each tool. A tool is **one `case` arm** that contributes to the
phases; there is no table format to parse at runtime and no per-tool install
function.

Phases, in order:

1. **`SCRIPT_VERSION` constant**, echoed as the first line of output (section 8).
2. **Lockfile block** — the pins from section 4.
3. **Parse and validate arguments** — one `case` over `"$@"`. Each arm appends to
   accumulator arrays rather than installing anything; the `*)` arm is the fatal
   unknown-name error, so validation completes before any install work. Add-on
   parent checks run here too.
4. **Repository setup** — each unique apt repository set up once, guarded.
5. **One `apt-get update`.**
6. **One `apt-get install`** with every pinned package.
7. **Non-apt installs** — today only `uv tool install` for `snow`.
8. **Plugin block** — `claude plugin marketplace add` / `install`, now fatal.
9. **`settings.json`** — the `jq` write. Still the last *write* in the file.
10. **Verification** — the section 6 gate. It only *reads*, including the
    `settings.json` read-back, so it sits below the settings write without
    breaking the settings-last constraint.

The accumulator shape:

```bash
for tool in "$@"; do
  case "$tool" in
    gcloud)  repos+=(google);    apt_pkgs+=("google-cloud-cli=${GCLOUD_VERSION}") ;;
    kubectl) repos+=(k8s);       apt_pkgs+=("kubectl=${KUBECTL_VERSION}") ;;
    snow)    uv_pkgs+=("snowflake-cli==${SNOW_VERSION}") ;;
    *) fail "unknown tool: $tool" ;;
  esac
done
```

**Why phased rather than sequential.** A sequential loop would run `apt-get
update` once per tool and, worse, would make the outcome depend on argument
order: which repositories happen to be enabled when `kubectl` is installed
changes which `kubectl` you get. Collecting first and installing once, with every
package explicitly pinned, makes that collision structurally impossible.

Rejected: a runtime-parsed declarative table (structure at the cost of parsing
and quoting rules, for six rows); one install function per tool (incompatible
with batching into a single `apt-get install`); pins moved into the `case` arms
(the lockfile block is what gets reviewed on a version roll).

### Adding a sixth tool

1. One line in the lockfile block.
2. One `case` arm in the argument parser.
3. One `case` arm in the verification block.
4. One repository setup arm — **only** if the vendor is not already used.

Everything else is inherited: the presence guard, the failure collection and
single recap, the verification loop's structure. A short comment block above the
argument `case` carries this four-step checklist, so whoever adds a tool finds it
in the file they are already editing.

Outside the file, adding a tool also means a `SCRIPT_VERSION` MINOR bump, a tag
cut by CD, and a box edit in each environment that wants it.

## 8. Versioning, tagging and release

([#22](https://github.com/mattiasthalen/claude-cloud-environment/issues/22))

- **Tag format**: full three-field `vMAJOR.MINOR.PATCH`, starting at `v1.0.0`.
  Truncated forms (`v1`, `v1.2`) are rejected — they tempt a moving tag.
  - **MAJOR** — the box invocation itself must change (argument renamed or
    removed, tool name changed, new required argument).
  - **MINOR** — new capability, old box text still valid (new tool row, new
    add-on, new verification output).
  - **PATCH** — pin bumps and fixes; nothing about the box changes.
- **`main` is deployed nowhere; only tags are.** `main` may sit ahead of every
  environment indefinitely. `main` is the single development branch, every tag is
  cut from a `main` commit, and a fix is a new tag rather than a patch to an old
  one.
- **`SCRIPT_VERSION` is the single source of truth.** A constant near the top of
  `environment.sh`, echoed as the **first line of output** so it is visible even
  when the run dies early, and not repeated in the verification summary. The echo
  reports what the environment is really running, which is better truth than the
  box text.
- **Pushing a bumped `SCRIPT_VERSION` to `main` is the release.** CD on push to
  `main` reads the constant; if no tag of that name exists it creates the tag at
  that commit and the GitHub Release (`contents: write`). Constant unchanged →
  silent no-op. Tag already exists → silent skip. Non-increasing version → fail
  loudly.
- **CI on `pull_request`** checks version format and strict monotonicity against
  the highest existing tag, blocking the merge. CD re-checks monotonicity anyway,
  because nothing forces PRs on this repository. The CI job covers the version
  check only.
- **Changelog**: a GitHub Release per tag, body = the bump commit's message body
  with GitHub's generated notes appended. The commit message carries urgency
  ("pin bump, roll when convenient" / "fixes a broken install, roll now"), which
  a `git log` diff cannot express. No `CHANGELOG.md`.
- **Rolling**: environments may sit on different tags. Roll one first to prove the
  change, then roll the rest promptly. Convergence is the expected norm;
  divergence is a transient state during a roll, not a resting state, and is not
  enforced.
- **`v1.0.0` is cut when this spec is implemented**, not against today's pre-spec
  script.

Rejected: date-stamped tags, tracking `main` (a push changes nothing in any
environment until each snapshot expires on its own clock, and forcing a rollout
still requires a box edit), and pinning a bare commit SHA (the script cannot echo
a SHA that does not exist until after the commit, leaving a comment that can
drift as the only staleness signal).

## 9. Out of scope

- **Authentication and credential provisioning** for any CLI — each environment's
  own box, deliberately not this repository.
- **Client-specific configuration** (project IDs, subscriptions, accounts,
  warehouses) — same reason, and it would leak client identity into a repository
  that must not carry it.
- **`snow` plugins.** There is no `snow plugin install`: a plugin is a PyPI
  package installed into the CLI's own uv environment and then enabled by writing
  `[cli.plugins.<name>] enabled = true` into `~/.config/snowflake/config.toml` —
  the same file that holds connection credentials. Installing without enabling is
  inert, so the only in-scope option would breach the no-credentials boundary.
  Reversible the moment an environment actually needs one.
- **`kubectl` plugins via krew.** `krew install` has no `--version` flag, and
  `pkgs.k8s.io` ships no plugin packages, so adopting it would extend the single
  unpinned-tool carve-out that `acli` holds for a stated reason.
- **Automated staleness detection for pins** (a scheduled job comparing each pin
  against upstream latest). The hard fail on a dead pin is already a forcing
  function, and weekly cache expiry surfaces one quickly. Needs its own workflow.
- **`acli` add-ons.** No mechanism exists — a single static Go binary.
- **Changing `environment.sh` itself.** This effort produces the spec; the
  implementation is separate work.

## 10. Known gaps

Recorded on the map as fog, deliberately not settled here:

- **Keeping four setup-script boxes in sync.** The per-environment tool list lives
  only in the box, with no record anywhere of which environment gets which tools.
- **Lint and syntax CI** (`shellcheck`, `bash -n`) for `environment.sh`.
- **Portability.** Everything above is pinned to noble/x86_64/root, and the base
  image is Anthropic's to change. Whether the script should degrade gracefully or
  fail fast when it does is undecided.
- **Who does what when a tool is added later** — repository change plus tag bump
  plus four box edits, ownership unassigned.
