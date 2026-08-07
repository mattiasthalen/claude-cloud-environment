# Claude Code on the web: what a cloud environment can configure

Research for [issue #13](https://github.com/mattiasthalen/claude-cloud-environment/issues/13), under the map in [issue #10](https://github.com/mattiasthalen/claude-cloud-environment/issues/10).

Question: does Claude Code on the web offer a supported pre-baked-tooling mechanism — a custom base image, a Dockerfile, a persisted snapshot — that would make setup-time installation the wrong layer for per-environment CLI tooling?

## Verdict

**A custom base image is not a viable alternative for Anthropic-hosted cloud environments.** The documentation states plainly that replacing the base image is not supported, and names the setup script as the intended way to customise it. The setup script therefore remains the correct layer, and the rest of the map stands.

One qualification: an organisation-controlled image does exist, but only through **self-hosted environments**, a separate public-beta product on Team and Enterprise plans where the organisation builds and operates its own runner image and fleet. That is a different deployment model with its own operational burden, not a configuration option on an Anthropic-hosted environment.

Sources are the official Claude Code documentation at `code.claude.com`. Where the documentation does not answer a question, that is stated rather than inferred.

## 1. What an environment can configure

An Anthropic-hosted cloud environment has exactly four configurable fields, all in one dialog reached from the environment selector at `claude.ai/code`: **name**, **network access level**, **environment variables**, and **setup script**.

> Select **Add cloud environment**, or hover over an existing environment and select the settings icon that appears on the right. The dialog includes the name, network access level, environment variables, and setup script.

— [Configure cloud environments § Configure your environment](https://code.claude.com/docs/en/cloud-environments#configure-your-environment)

Organisation-shared environments, created by Owners and admins on Team and Enterprise plans, carry the same four fields and nothing more ([§ Organization-shared environments](https://code.claude.com/docs/en/cloud-environments#organization-shared-environments)).

There is **no base-image field** and **no secrets store**:

> Anyone who uses the environment can read the values, and cloud environments have no dedicated secrets store, so don't add API keys or other credentials.

— [§ Set environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)

The image itself is fixed: every Anthropic-hosted session gets a fresh Ubuntu 24.04 VM with a documented pre-installed toolchain list, and setup scripts run as root on it ([§ What's available in cloud sessions](https://code.claude.com/docs/en/cloud-environments#whats-available-in-cloud-sessions), [§ Installed tools](https://code.claude.com/docs/en/cloud-environments#installed-tools), [§ Setup scripts](https://code.claude.com/docs/en/cloud-environments#setup-scripts)). Resource ceilings are approximately 4 vCPUs, 16 GB RAM and 30 GB disk ([§ Resource limits](https://code.claude.com/docs/en/cloud-environments#resource-limits)). Toolchains outside the pre-installed list — the documentation's own example is the .NET SDK — are to be installed with a setup script ([§ Installed tools](https://code.claude.com/docs/en/cloud-environments#installed-tools)).

## 2. Custom image or Dockerfile

Not supported on Anthropic-hosted environments. The documentation is explicit:

> To customize the base image, use a setup script to install what you need on top of the [provided image](https://code.claude.com/docs/en/cloud-environments#installed-tools), or run your own image as a container alongside Claude with `docker compose`. **Replacing the base image entirely isn't supported yet.**

— [§ Limitations in cloud sessions](https://code.claude.com/docs/en/cloud-environments#limitations-in-cloud-sessions)

Two adjacent mechanisms exist, neither of which replaces the base image:

- **Docker as a sidecar.** Docker, dockerd and docker compose are pre-installed, and the documentation suggests putting `docker compose pull` or `docker compose build` in the setup script so the environment cache keeps the pulled images. The cache stores files, not running processes, so containers still have to be started each session ([§ Start services](https://code.claude.com/docs/en/cloud-environments#start-services)). This puts a custom image *next to* Claude, not *under* it: Claude's own shell, and therefore any CLI it invokes directly, still runs on the provided image.
- **Self-hosted environments.** Sessions routed to a self-hosted environment "run on your own runners instead, with the tools your runner image provides" ([§ What's available in cloud sessions](https://code.claude.com/docs/en/cloud-environments#whats-available-in-cloud-sessions)). Here a Dockerfile genuinely is the tool-selection mechanism — "Anthropic doesn't publish a pre-built runner image. Build your own around the `claude` binary, layering in whatever toolchain your repositories need" ([Deploy to production § Build the runner image](https://code.claude.com/docs/en/self-hosted-environments-deploy#build-the-runner-image)), and one of the stated reasons to self-host is "pre-install compilers, SDKs, and internal CLIs in your runner image so every session starts ready to build" ([Self-hosted environments § Why self-host](https://code.claude.com/docs/en/self-hosted-environments#why-self-host)). It is public beta on Team and Enterprise plans only, off by default, and requires the organisation to build the image, operate the runner fleet and control its network ([§ Availability and limitations](https://code.claude.com/docs/en/self-hosted-environments#availability-and-limitations)). Under that model, per-environment tool selection would be expressed as one runner image per environment, since an environment is a named group of runners.

The documentation does not state whether an environment's setup script and environment variables are applied to sessions running on self-hosted runners. That question is unanswered by the sources consulted.

## 3. When the setup script runs, and what triggers a rebuild

The setup script does **not** run every session. It runs once, and the resulting filesystem is snapshotted and reused:

> The setup script runs the first time you start a session in an environment. After it completes, Anthropic snapshots the filesystem and reuses that snapshot as the starting point for later sessions. New sessions start with your dependencies, tools, and Docker images already on disk, and skip the setup script step.

— [§ Environment caching](https://code.claude.com/docs/en/cloud-environments#environment-caching)

Rebuild triggers are enumerated exactly:

> The setup script runs again to rebuild the cache when you change the environment's setup script or allowed network hosts, and when the cache reaches its expiry after roughly seven days. Resuming an existing session never re-runs the setup script.

— [§ Environment caching](https://code.claude.com/docs/en/cloud-environments#environment-caching)

So: a setup-script edit, an allowed-network-hosts edit, or roughly seven days of cache age. Changing the environment's **variables** is not listed as a rebuild trigger. The cache is a filesystem snapshot, so installed packages, pulled Docker images and written files carry over, while anything that was merely running does not.

Two constraints follow for anything written into the setup script ([§ Script requirements](https://code.claude.com/docs/en/cloud-environments#script-requirements)):

- **Exit zero.** "If the script exits non-zero, the session fails to start." The documentation recommends `|| true` on non-critical commands — worth noting against this repo's stated fail-loudly policy, since that recommendation trades a failed session for a silently incomplete one.
- **Roughly five minutes.** The script's total runtime must stay "under roughly five minutes so the environment cache can build." Independent installs can be parallelised with `&` and `wait`; a single download that will not fit is meant to move to a SessionStart hook that backgrounds it.

The ordering relative to Claude Code is fixed: the setup script runs first, before Claude Code launches and only when no cached environment exists; SessionStart hooks run afterwards, on every session including resumed ones ([§ Setup scripts vs. SessionStart hooks](https://code.claude.com/docs/en/cloud-environments#setup-scripts-vs-sessionstart-hooks)).

## 4. Whether the network policy can block downloads, and how that surfaces

Yes, it can. An environment has one of four network access levels — **None** (no outbound access), **Trusted** (the default allowlist), **Full** (any domain), and **Custom** (your own list, with an optional checkbox to also include the defaults) ([§ Access levels](https://code.claude.com/docs/en/cloud-environments#access-levels), [§ Allow specific domains](https://code.claude.com/docs/en/cloud-environments#allow-specific-domains)). A Custom list without the defaults checkbox allows only what is listed and nothing else. All outbound traffic from an Anthropic-hosted session additionally passes through a security proxy that does content filtering and rate limiting, and some package managers are known not to work correctly with it — Bun is the named example ([§ Security proxy](https://code.claude.com/docs/en/cloud-environments#security-proxy), [§ Limitations in cloud sessions](https://code.claude.com/docs/en/cloud-environments#limitations-in-cloud-sessions)).

The default **Trusted** allowlist is published in full at [§ Default allowed domains](https://code.claude.com/docs/en/cloud-environments#default-allowed-domains). Relevant to the CLIs in issue #10, it **does** include:

- `archive.ubuntu.com`, `security.ubuntu.com`, `*.ubuntu.com`, `ppa.launchpad.net`, `launchpad.net` — so `apt` against the distro repositories works.
- `dl.k8s.io`, `pkgs.k8s.io`, `k8s.io` — both `kubectl` install routes.
- `packages.microsoft.com`, plus `azure.com`, `*.microsoftonline.com`, `dev.azure.com` — the Azure CLI apt repository.
- `cloud.google.com`, `gcloud.google.com`, `accounts.google.com`, `*.googleapis.com`, `storage.googleapis.com`.
- Container registries (Docker Hub, `gcr.io`, `ghcr.io`, `mcr.microsoft.com`, `public.ecr.aws`) and the usual language registries.

It does **not** list some domains that specific vendor install routes use, notably `packages.cloud.google.com` (the Google Cloud CLI apt repository), `dl.google.com`, or any Snowflake or Atlassian host. The documentation publishes the list but does not comment on which install route for a given CLI it is sufficient for, so treat any specific tool's installability as something to verify rather than read off the list.

On how failure surfaces, the documentation is thin. What it does say:

- "**Network access for installs**: package installs need to reach registries. The default **Trusted** level covers common package registries including npm, PyPI, RubyGems, and crates.io; with **None** network access, installs fail." ([§ Script requirements](https://code.claude.com/docs/en/cloud-environments#script-requirements))
- A failing install that makes the script exit non-zero means "the session fails to start" ([§ Script requirements](https://code.claude.com/docs/en/cloud-environments#script-requirements)).
- The one documented concrete status code is unrelated to the allowlist: "GitHub API and release-asset requests reach only repositories attached to the session, so a setup script that downloads release assets from an unattached repository gets a 403" ([§ GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy)).

The documentation does **not** describe what a request to a non-allowlisted domain returns — no error text, status code, DNS-versus-connect distinction, or proxy response is documented. It also does not describe where setup-script output or a setup-script failure is displayed, beyond the CLI's live checklist of setup steps shown while the container starts ([Claude Code on the web § From terminal to web](https://code.claude.com/docs/en/claude-code-on-the-web#from-terminal-to-web)).

## 5. Are environment variables applied after the setup script?

**Neither confirmed nor refuted by the documentation.** No page consulted states the ordering of environment-variable injection relative to setup-script execution.

The closest statements, and what they do and do not settle:

- "Each session copies the environment's values once, at startup, into ordinary environment variables that any command Claude runs can read." ([§ Set environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)) — "any command Claude runs" is about the session, and the setup script runs before Claude Code launches, so this sentence does not cover the setup script either way.
- "Setup scripts and SessionStart hooks run in a fixed order" ([§ Setup scripts vs. SessionStart hooks](https://code.claude.com/docs/en/cloud-environments#setup-scripts-vs-sessionstart-hooks)) — that ordered list covers only those two, and does not place variable injection in it.
- Weak evidence pointing the other way: of a `GH_TOKEN` set in environment settings, "it passes through to the container unchanged, so your scripts, and GitHub's `gh` CLI if you install it, use it directly" ([§ Work with GitHub issues and pull requests](https://code.claude.com/docs/en/cloud-environments#work-with-github-issues-and-pull-requests)). "Your scripts" is not defined, and the same passage tells you to install `gh` from the setup script, so this hints at but does not establish that a setup script sees the variables.

Independently of the ordering, the caching model makes environment variables an unsound selection transport for the setup script. The snapshot is built once and shared by every later session in that environment, and editing the variables is not among the documented rebuild triggers ([§ Environment caching](https://code.claude.com/docs/en/cloud-environments#environment-caching)). A setup script that branched on a variable would bake whichever value was current at build time into the snapshot, and a later change to that variable would not rebuild it. The map's working assumption — that selection must ride inline on the setup-script line — therefore holds on cache grounds even though the documentation does not confirm the ordering claim itself.

## Consequences for the map

- The setup script is the right layer. There is no supported image-level alternative on Anthropic-hosted environments, so the spec in issue #10 is not being written at the wrong altitude.
- Install cost is paid on rebuild, not per session, which the map already assumes. Rebuild triggers are narrow and enumerable: setup-script edit, allowed-hosts edit, and roughly seven-day cache expiry. The seven-day expiry is worth recording, since it means an unpinned install is re-run weekly and can drift — supporting the map's version-pinning decision.
- The five-minute setup-script budget is a real constraint on installing several cloud CLIs in one script, and points at parallel installs with `&` and `wait`.
- The documentation's `|| true` recommendation conflicts with the map's fail-loudly policy. The tension is resolvable — a failed critical install should fail the session — but the spec should say so deliberately.
- Selection cannot ride on environment variables, for cache reasons if not for ordering reasons.
- The Trusted allowlist covers the distro repositories and several vendor repositories, but not every vendor's install route. Per-tool install research should check each chosen route against the published list, and note that a Custom allowlist edit is itself a rebuild trigger.
- Self-hosted environments remain a genuine but heavyweight escape hatch: Team or Enterprise, public beta, and the organisation owns the image and the fleet.

## Sources

- [Use Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
- [Configure cloud environments](https://code.claude.com/docs/en/cloud-environments)
- [Self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments)
- [Deploy self-hosted environments to production](https://code.claude.com/docs/en/self-hosted-environments-deploy)

Documentation read on 2026-08-07.
