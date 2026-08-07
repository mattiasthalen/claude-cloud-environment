# CLI install methods on Ubuntu 24.04 as root

Research for [issue #12](https://github.com/mattiasthalen/claude-cloud-environment/issues/12), part of the map in [issue #10](https://github.com/mattiasthalen/claude-cloud-environment/issues/10).

Question: for `gcloud`, `az`, `kubectl`, `snow` and `acli`, what is the officially supported non-interactive install on Ubuntu 24.04 (noble), x86_64, as root; can an exact version be pinned; what prerequisites are needed; how long does it take and how much disk does it use; and is the binary usable immediately.

Authentication is out of scope throughout.

## Method

Every claim below is taken from the vendor's own documentation, and every install was then run for real in an Ubuntu 24.04.4 LTS x86_64 container as root, matching the target environment. Timings and disk figures are measured, not estimated. Measurements were taken on a container with a fast network; download time will dominate on a slower link.

Verified environment: `Ubuntu 24.04.4 LTS`, `x86_64`, `root`, with `curl`, `jq`, `git`, `python3`, `pip`, `uv`, `node`/`npm` present and no `gh` or `pipx`.

## Summary table

| Tool | Install method | Pin syntax | Prerequisites | Time | Disk | Usable immediately |
| --- | --- | --- | --- | --- | --- | --- |
| `gcloud` | Google Cloud apt repository, package `google-cloud-cli` | `apt-get install -y google-cloud-cli=579.0.0-0` | Keyring at `/usr/share/keyrings/cloud.google.gpg`, source list, `apt-get update` | 33 s | 883 MB | Yes |
| `az` | Microsoft apt repository, package `azure-cli` | `apt-get install -y azure-cli=2.89.0-1~noble` | Keyring at `/etc/apt/keyrings/microsoft.gpg`, deb822 source, `apt-get update` | 11 s | 636 MB | Yes |
| `kubectl` | `pkgs.k8s.io` apt repository, package `kubectl` | `apt-get install -y kubectl=1.34.10-1.1` (minor version also fixed in the repository URL) | Keyring at `/etc/apt/keyrings/kubernetes-apt-keyring.gpg`, source list, `apt-get update`. See the collision warning below | 4 s | 58 MB | Yes |
| `snow` | `uv tool install` from PyPI | `uv tool install 'snowflake-cli==3.16.0'` | `uv` and a Python 3.10+ interpreter; no apt repository | 3 s | 147 MB | Yes |
| `acli` | Atlassian apt repository, package `acli` | Not usefully pinnable: the repository carries exactly one version | Keyring at `/etc/apt/keyrings/acli-archive-keyring.gpg`, source list, `apt-get update` | 2 s | 16 MB | Yes |

Total for all five: roughly 53 seconds and 1.74 GB, against the ~30 GB of writable space available.

## Cross-cutting prerequisites

- `apt-get update` is required after adding any repository, and only needs to run once if all repositories are added first. A single combined `apt-get update` across all four vendor repositories took about 2 seconds.
- Every apt install must carry `-y`. Setting `DEBIAN_FRONTEND=noninteractive` is a cheap belt-and-braces measure; in practice none of the four packages asked a debconf question during these runs.
- Running as root means no `sudo` is needed anywhere. The vendor documentation is written with `sudo`, which is harmless but unnecessary.
- All four vendor repositories serve over HTTPS and all four keyrings fetched cleanly. `ca-certificates`, `curl` and `gnupg` are already present in the base image, so the documented "install prerequisites" step is a no-op here.

## Per-tool detail

### `gcloud` (Google Cloud CLI)

Primary source: [Install the gcloud CLI](https://docs.cloud.google.com/sdk/docs/install), Debian/Ubuntu tab.

```bash
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  > /etc/apt/sources.list.d/google-cloud-sdk.list
apt-get update
apt-get install -y google-cloud-cli=579.0.0-0
```

The documented pin syntax is `google-cloud-cli=123.0.0-0`, and the trailing `-0` is part of the Debian version string rather than the upstream version. This was confirmed against the live repository: `apt-get install -s google-cloud-cli=578.0.0-0` resolves correctly.

The documentation says "the ten most recent releases are always available in the repository." That understates it substantially. The live repository index currently lists **228** versions of `google-cloud-cli`, from 459.0.0 to 579.0.0. Pinning to a version well outside a ten-release window therefore works today, but the documented contract is only ten releases, so a pin should not be left to rot for long.

Measured install: 33 seconds, 883 MB on disk (`/usr/lib/google-cloud-sdk` is 876 MB of that). This is the largest of the five by a wide margin. The documentation notes that `CLOUDSDK_SKIP_PY_COMPILATION=1` can be exported during installation to reduce setup time in resource-constrained environments, at the cost of slower first invocation.

The package ships `gcloud`, `gcloud alpha`, `gcloud beta`, `gsutil` and `bq`, and bundles its own Python (3.14.6 in 579.0.0), so it does not depend on the system interpreter.

One behavioural consequence of the deb install matters for the wider spec: **the gcloud component manager is disabled**. Running `gcloud components install gke-gcloud-auth-plugin` fails with an explicit error directing you to `apt-get install google-cloud-cli-gke-gcloud-auth-plugin` instead. Optional components are therefore ordinary apt packages (`google-cloud-cli-gke-gcloud-auth-plugin`, `google-cloud-cli-kubectl-oidc`, `google-cloud-cli-minikube`, and roughly twenty more), which is good news for pinning and for the fail-loudly policy, since a missing component becomes an apt failure rather than a runtime surprise.

`gcloud version` runs immediately after install with no configuration.

### `az` (Azure CLI)

Primary source: [Install the Azure CLI on Linux](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux), apt tab. Microsoft explicitly lists Ubuntu 24.04 (Noble Numbat) as a tested distribution.

Microsoft offers two options. Option 1 is a piped install script, `curl -fsSL 'https://azurecliprod.blob.core.windows.net/$root/deb_install.sh' | bash`, which cannot pin a version. Option 2 is the step-by-step repository setup, which can:

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
apt-get update
apt-get install -y azure-cli=2.89.0-1~noble
```

Note this is a deb822 `.sources` file, not a one-line `.list` entry. The documented pin syntax is `azure-cli=${AZ_VER}-1~${AZ_DIST}`, so on noble the suffix is always `-1~noble`. Confirmed live: `apt-get install -s azure-cli=2.88.0-1~noble` resolves.

The noble repository currently carries **31** versions, 2.59.0 through 2.89.0. Because the distribution codename is baked into the version string, a pin written for one Ubuntu release will not resolve on another; that is acceptable given issue #10 fixes the base image at noble.

Measured install: 11 seconds, 636 MB on disk (`/opt/az`). `az version` returns clean JSON immediately, with no extensions installed and no configuration required.

Microsoft's documented alternative, `az upgrade`, is an in-tool updater and works directly against a pinned install, so it should not be invoked from a script that wants a pinned version.

### `kubectl`

Primary source: [Install and Set Up kubectl on Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/).

```bash
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubectl=1.34.10-1.1
```

Pinning here is two-layered. The **minor** version is fixed by the `v1.34` segment of the repository URL, and there is a separate repository per minor version; the upstream documentation is emphatic that moving to a different minor version means editing the source list, not just changing the package version. The **patch** version is then fixed by the ordinary apt `=` syntax, with the vendor's `-1.1` Debian revision suffix. The `v1.34` repository currently offers 1.34.0 through 1.34.10.

**A collision worth designing around.** The Google Cloud SDK repository also publishes a package named `kubectl`, and it uses an epoch: `1:579.0.0-0`. An epoch beats any version without one, so with both repositories enabled, a plain `apt-get install kubectl` silently installs Google's build rather than the upstream one. This was reproduced directly:

```
$ apt-get install -s kubectl
Inst kubectl (1:579.0.0-0 cloud-sdk:cloud-sdk [amd64])
```

Since environments in issue #10 may want both `gcloud` and `kubectl`, always installing `kubectl` with an explicit `=1.34.x-1.1` pin is not merely good hygiene, it is the only way to reliably get the upstream binary. An apt preferences pin on the `pkgs.k8s.io` origin would be an alternative, but it adds a second file to manage.

Measured install: 4 seconds, 58 MB. `kubectl version --client` reports `v1.34.10` immediately. `kubectl config view` returns an empty config with no error, so the binary is usable with no configuration; a context is of course needed before it can talk to a cluster.

The direct binary download is the documented alternative and works too:

```bash
curl -fsSLO https://dl.k8s.io/release/v1.34.10/bin/linux/amd64/kubectl
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

The download is 58 MB and took about 1 second. This route pins a full `x.y.z` in a single URL and needs no keyring or repository at all, which sidesteps the epoch collision entirely. Its cost is that it does not participate in apt's package database.

`https://dl.k8s.io/release/stable.txt` currently returns `v1.36.3`, so v1.34 is two minor versions behind stable and is chosen here only as the example under test.

### `snow` (Snowflake CLI)

Primary source: [Installing Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation).

There is no Snowflake apt repository. Snowflake documents two viable routes on Linux.

**Python tool install (recommended for this environment).** The documentation lists `uv tool install snowflake-cli`, `pipx install snowflake-cli` and `pip install snowflake-cli`, with an explicit caution against `pip` because it modifies the ambient Python environment. `pipx` is not present in the container, `uv` is, so `uv` is the natural choice.

```bash
UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 'snowflake-cli==3.16.0'
```

Pinning is ordinary PEP 508: `snowflake-cli==3.16.0`. Snowflake's documentation does not spell this out, but it is a plain PyPI distribution and the pin was verified to install exactly 3.16.0.

Two operational notes. First, the documentation requires Python 3.10 or later; passing `--python 3.12` makes the interpreter choice explicit rather than inheriting whatever `uv` happens to pick. Second, `uv tool install` places shims in `~/.local/bin` by default, which is not necessarily on `PATH` for a non-login shell; setting `UV_TOOL_BIN_DIR=/usr/local/bin` puts `snow` somewhere unambiguously on `PATH`.

Measured install: 3 seconds, 147 MB (`~/.local/share/uv/tools/snowflake-cli` is 139 MB of that). `snow --version` reports `Snowflake CLI version: 3.16.0` immediately, and `snow connection list` returns `No data` rather than erroring, so no configuration file is required for the binary to function.

**Versioned deb download.** Snowflake also publishes per-version `.deb` files:

```bash
curl -fsSLO https://sfc-repo.snowflakecomputing.com/snowflake-cli/linux_x86_64/3.24.1/snowflake-cli-3.24.1.x86_64.deb
dpkg -i snowflake-cli-3.24.1.x86_64.deb
```

The repository index at `https://sfc-repo.snowflakecomputing.com/snowflake-cli/index.html` lists every release from 3.0.2 to 3.24.1, so the version is pinned by the URL and the archive is far deeper than any of the apt repositories above. The 3.24.1 deb is 86 MB with an installed size of 88 MB, slightly leaner than the `uv` route because it bundles rather than resolving a dependency tree. The downside is that it is `dpkg -i` rather than `apt-get install`, so dependency resolution and idempotency are the caller's problem, and the download URL must be constructed by hand.

Snowflake's own text says it recommends "binary installation methods, such as package managers" in general, which reads as a nudge towards the deb; but for a script that already has `uv`, the `uv` route is one line, pins cleanly, and is explicitly documented.

### `acli` (Atlassian CLI)

Primary source: [Install Atlassian CLI on Linux](https://developer.atlassian.com/cloud/acli/guides/install-linux/).

```bash
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://acli.atlassian.com/gpg/public-key.asc \
  | gpg --dearmor -o /etc/apt/keyrings/acli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/acli-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/acli-archive-keyring.gpg] https://acli.atlassian.com/linux/deb stable main" \
  > /etc/apt/sources.list.d/acli.list
apt-get update
apt-get install -y acli
```

Atlassian's documented steps use `wget` for the key; `curl` works identically and is already present, so the `wget gnupg2` prerequisite step can be skipped here.

**Version pinning is effectively unavailable.** The `stable` repository index contains exactly one version, currently `1.3.22~stable`. `apt-cache madison acli` returns a single line. There is no versioned apt suite, and the documented direct-download URLs all go through `/latest/`:

```
https://acli.atlassian.com/linux/latest/acli_linux_amd64/acli
https://acli.atlassian.com/linux/latest/acli_linux_amd64.tar.gz
```

Atlassian's "Download supported packages" page documents no versioned URL pattern. So `acli` is the one tool of the five where a container rebuild can silently move the version, and issue #10's "pin tool versions" requirement cannot be satisfied from primary sources. The practical mitigations, none of them wonderful, are to record the expected version and assert it after install (`acli --version` prints `acli version 1.3.22-stable`), or to mirror a known-good deb somewhere the script controls. Atlassian also notes that each version is supported for only six months after release, which suggests they consider drift the intended behaviour.

Measured install: 2 seconds, 16 MB via apt; the standalone binary is 17 MB. `acli --version` works immediately with no configuration.

## Recommendation

The working hypothesis in issue #12 holds for four of the five tools, and the fifth is a genuine gap.

1. **Use the vendor apt repository for `gcloud`, `az`, `kubectl` and `acli`.** All four are first-party, all four work non-interactively on noble as root, all four need only a keyring plus a source file plus one shared `apt-get update`. Adding all four repositories before a single `apt-get update` keeps the cost to about two seconds regardless of how many tools a given environment selects.

2. **Use `uv tool install` for `snow`,** with `UV_TOOL_BIN_DIR=/usr/local/bin` and an explicit `--python 3.12`. It is documented, it pins with `==`, and it avoids the ambient-Python hazard Snowflake warns about. The versioned deb at `sfc-repo.snowflakecomputing.com` is the fallback if the Python dependency ever becomes awkward, and it has a much deeper version archive.

3. **Always pin `kubectl` explicitly, even when `kubectl` is the only Kubernetes tool selected.** The epoch collision with the Google Cloud SDK repository means an unpinned install silently changes meaning the moment `gcloud` is also selected. This is the single most likely way for the finished script to be quietly wrong.

4. **Treat `acli` as an explicit exception to the pinning rule** and say so in the spec rather than leaving it implicit. The most honest thing the script can do is install whatever `stable` offers and then assert the version it got, failing loudly if it has moved.

5. **Budget roughly one minute and 1.8 GB for the full set.** `gcloud` alone is 883 MB and `az` 636 MB, so the two together are 87 percent of the footprint. Per-environment selection is worth real disk, not just tidiness. Since containers are cached and issue #10 already accepts slow-but-correct, none of these timings constrain the design.

6. **All five binaries are usable immediately with no configuration.** Every tool answered a version query straight after install, and `kubectl config view` and `snow connection list` both returned empty rather than erroring. Nothing in this set needs a post-install initialisation step before authentication can be layered on elsewhere.

One finding sharpens a "not yet specified" item in issue #10: because the deb install disables the gcloud component manager, optional gcloud components are ordinary apt packages and can be pinned, selected and failed-loudly exactly like the base package. That removes `gcloud components` from the list of post-install configuration questions.

## Sources

All primary vendor documentation, retrieved 2026-08-07:

- Google Cloud CLI: <https://docs.cloud.google.com/sdk/docs/install>
- Azure CLI: <https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux>
- kubectl: <https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/>
- Snowflake CLI: <https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation>
- Snowflake CLI package repository: <https://sfc-repo.snowflakecomputing.com/snowflake-cli/index.html>
- Atlassian CLI, Linux: <https://developer.atlassian.com/cloud/acli/guides/install-linux/>
- Atlassian CLI, supported packages: <https://developer.atlassian.com/cloud/acli/guides/download-supported-packages/>

Version numbers observed in the live repositories on 2026-08-07: `google-cloud-cli` 579.0.0-0, `azure-cli` 2.89.0-1~noble, `kubectl` 1.34.10-1.1 (upstream stable `v1.36.3`), `snowflake-cli` 3.24.1, `acli` 1.3.22~stable.
