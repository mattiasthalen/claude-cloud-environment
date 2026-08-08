# CLI add-on and extension mechanisms on Ubuntu 24.04 as root

Research supporting [issue #20](https://github.com/mattiasthalen/claude-cloud-environment/issues/20), part of the map in [issue #10](https://github.com/mattiasthalen/claude-cloud-environment/issues/10).

Question: for `gcloud`, `az`, `kubectl`, `snow` and `acli`, what optional add-on, extension or plugin mechanism exists; can an add-on be version-pinned; can it be installed non-interactively and idempotently; and where does it land on disk.

Authentication and per-client configuration are out of scope throughout, as they are for the whole map.

## Method

Every claim below is either taken from the vendor's own documentation or measured by running the command in an Ubuntu 24.04 x86_64 container as root, matching the target environment. Where both exist, the measured result is given and the documentation is cited alongside. Claims that are documentation-only are marked as such.

## Summary table

| CLI | Mechanism | Install command | Pinnable | Idempotent |
| --- | --- | --- | --- | --- |
| `gcloud` | Separate apt packages; the bundled component manager is disabled | `apt-get install -y google-cloud-cli-<component>=579.0.0-0` | Yes — same version string as the base package, in lockstep | Yes |
| `az` | `az extension` | `az extension add -n <name> --version <v> -y` | Yes — `--version`, or `--source <wheel-url>` | Yes (warns, exits 0) |
| `kubectl` | krew (no apt-level plugin packages) | krew bootstrap, then `kubectl krew install <name>` | krew itself yes, by release tag; **plugins no** | Yes |
| `snow` | Entry-point plugins; the CLI can only enable, not install | `uv tool install snowflake-cli --with <pkg>==<v>`, then `snow plugin enable <name>` | Yes — a PyPI pin | Partial: reinstall needs `--force`; enable is idempotent |
| `acli` | None | — | n/a | n/a |

## `gcloud` components

The Debian package ships with the component manager switched off. Measured: extracting `usr/lib/google-cloud-sdk/lib/googlecloudsdk/core/config.json` from the deb shows `"disable_updater": true`, so `gcloud components install` does not work on an apt install. Components are separate apt packages from the same repository ([external package managers](https://cloud.google.com/sdk/docs/components#external_package_managers)).

Measured with `apt-cache pkgnames google-cloud` after adding `deb https://packages.cloud.google.com/apt cloud-sdk main` and running `apt-get update`, the repository carries 40 packages under the modern `google-cloud-cli-` prefix:

```
google-cloud-cli                       (base)
google-cloud-cli-anthos-auth
google-cloud-cli-anthoscli
google-cloud-cli-app-engine-go
google-cloud-cli-app-engine-grpc
google-cloud-cli-app-engine-java
google-cloud-cli-app-engine-python
google-cloud-cli-app-engine-python-extras
google-cloud-cli-bigtable-emulator
google-cloud-cli-cbt
google-cloud-cli-cloud-build-local
google-cloud-cli-cloud-run-proxy
google-cloud-cli-config-connector
google-cloud-cli-datalab
google-cloud-cli-datastore-emulator
google-cloud-cli-docker-credential-gcr
google-cloud-cli-enterprise-certificate-proxy
google-cloud-cli-firestore-emulator
google-cloud-cli-gke-gcloud-auth-plugin
google-cloud-cli-harbourbridge
google-cloud-cli-istioctl
google-cloud-cli-kpt
google-cloud-cli-kubectl-oidc
google-cloud-cli-local-extract
google-cloud-cli-log-streaming
google-cloud-cli-managed-flink-client
google-cloud-cli-minikube
google-cloud-cli-nomos
google-cloud-cli-package-go-module
google-cloud-cli-pubsub-emulator
google-cloud-cli-run-compose
google-cloud-cli-sbom-extractor
google-cloud-cli-skaffold
google-cloud-cli-spanner-cli
google-cloud-cli-spanner-emulator
google-cloud-cli-spanner-migration-tool
google-cloud-cli-terraform-tools
google-cloud-cli-terraform-validator
google-cloud-cli-tests
google-cloud-cli-universal-maker
```

The legacy `google-cloud-sdk-*` names (35 packages) are still present as compatibility aliases; prefer the `google-cloud-cli-` names. The same repository also ships `kubectl` under its bare name — see the collision warning in [the install-methods research](cli-install-methods.md).

### Pinning

Components version in lockstep with the base package. Measured: `google-cloud-cli`, `-gke-gcloud-auth-plugin`, `-app-engine-python`, `-terraform-tools`, `-minikube`, `-skaffold`, `-kpt`, `-nomos`, `-anthos-auth` and `-config-connector` all had candidate `579.0.0-0`, and `apt-cache madison` showed identical version ladders for each (579.0.0-0, 578.0.0-0, 577.0.0-0, 576.0.0-0, 575.0.1-0, 575.0.0-0, …). So one pin string covers the base package and every component:

```
apt-get install -y google-cloud-cli=579.0.0-0 google-cloud-cli-gke-gcloud-auth-plugin=579.0.0-0
```

Two things must be pinned explicitly rather than inferred:

- **Each package needs its own `=<version>`.** Measured via `apt-cache show`: component packages declare `Depends: google-cloud-cli` *unversioned*, and `google-cloud-cli-gke-gcloud-auth-plugin` declares no `Depends` at all. apt will not match versions across the set on its own.
- **`kubectl` from this repository carries an epoch**, `1:579.0.0-0`, not `579.0.0-0`. Different pin string from every other package here.

The base package only `Suggests:` its components, so installing `google-cloud-cli` pulls none of them, and installing a component pulls no base package.

Installs are idempotent, as apt installs are, and non-interactive with `DEBIAN_FRONTEND=noninteractive apt-get install -y`.

### `gke-gcloud-auth-plugin` is required for GKE

Documentation, from [GKE cluster access for kubectl](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl): "You must install this plugin to use `kubectl` and other clients to interact with GKE. Existing clients display an error message if the plugin is not installed." The cause is the removal of the in-tree GKE auth provider in Kubernetes 1.26, replaced by the client-go credential-plugin framework; see also the [kubectl auth changes in GKE announcement](https://cloud.google.com/blog/products/containers-kubernetes/kubectl-auth-changes-in-gke).

The documentation's suggested `gcloud components install gke-gcloud-auth-plugin` does not apply to an apt install, per the disabled updater above. Use the apt package.

Note for version assertions: `gke-gcloud-auth-plugin --version` prints a Kubernetes client version, not the apt version, so it cannot be compared against the apt pin.

## `az` extensions

Measured against `azure-cli` 2.89.0 installed from `https://packages.microsoft.com/repos/azure-cli/ noble main`.

- **Mechanism**: `az extension add`. There are no apt packages for extensions — measured, `apt-cache pkgnames azure` against the Microsoft repository returns only `azure-cli`, `azure-proxy-agent` and `azure-vm-utils`.
- **Pinning works.** Measured: `az extension add --name ssh --version 2.0.3 -y` then `az extension list` reports `ssh 2.0.3`, not the latest. An unavailable version fails loudly: `ERROR: Version '99.9.9' not found for extension 'account'`. Available versions come from `az extension list-versions --name <name> -o table`; the index does not carry every release (measured, `account` offers 0.1.0, 0.2.0, 0.2.1, 0.2.4 and 0.2.5, but not 0.2.3). A wheel can be pinned directly with `--source <url-or-path-to-.whl>`.
- **Idempotent, softly.** Measured: re-adding an already-installed extension at the same version prints `WARNING: Extension 'account' 0.2.5 is already installed.` and exits **0**. The `--upgrade` variant also exits 0.
- **Non-interactive** with `-y`/`--yes`.
- **Install path is per-user.** Measured: as root, extensions land in `/root/.azure/cliextensions/<name>`. From the source constant in `azure/cli/core/extension/__init__.py`, `EXTENSIONS_DIR` is `$AZURE_EXTENSION_DIR` if set and otherwise `~/.azure/cliextensions`, while `EXTENSIONS_SYS_DIR` is `$AZURE_EXTENSION_SYS_DIR` if set and otherwise `<purelib>/azure-cli-extensions` — here `/opt/az/lib/python3.14/site-packages/azure-cli-extensions`. The loader scans both. So `az extension add --system` writes to the system directory and makes the extension readable by any user, while a plain `add` binds it to the installing user's `$HOME`. Setting `AZURE_EXTENSION_DIR` to a shared exported path is the other option.
- **Preview and index overrides**: `--allow-preview {true,false}` on `az extension add`. The index URL comes from `AZURE_EXTENSION_INDEX_URL` first and the `extension.index_url` config second (measured in `azure/cli/core/extension/_index.py`). Dynamic auto-install is governed by `extension.use_dynamic_install` (`no` / `yes_prompt` / `yes_without_prompt`), `extension.run_after_dynamic_install` and `extension.dynamic_install_allow_preview`. `--pip-extra-index-urls` and `--pip-proxy` control dependency resolution.

References: [extensions overview](https://learn.microsoft.com/en-us/cli/azure/azure-cli-extensions-overview), [`az extension` reference](https://learn.microsoft.com/en-us/cli/azure/extension).

## `snow` plugins

Measured against `snowflake-cli` 3.24.1 installed with `uv tool install`, environment at `/root/.local/share/uv/tools/snowflake-cli/`.

- **There is no `snow plugin install`.** Measured: the `snow plugin` command group has exactly three subcommands — `list`, `enable`, `disable`.
- A plugin is an ordinary Python package registering a setuptools entry point in the group `snowflake.cli.plugin.command` (measured: `SNOWCLI_COMMAND_PLUGIN_NAMESPACE` in `snowflake/cli/api/plugins/command/__init__.py`, discovered via `importlib.metadata.entry_points` in `snowflake/cli/_plugins/plugin/manager.py`). It must live in the same environment as `snow`, so the install is `uv tool install snowflake-cli --with <package>==<version>`.
- After installing, the plugin must be enabled: `snow plugin enable <name>` writes `[cli.plugins.<name>] enabled = true` into `~/.config/snowflake/config.toml` (measured path from `snow --info`: `/root/.config/snowflake/config.toml`). That is the same file that holds connection definitions.
- Measured baseline: `snow plugin list` reports no data. No plugins ship by default.
- **No feature extras.** Measured from the PyPI metadata for 3.24.1, `provides_extra` is `["development", "packaging"]` — neither is a user-facing feature add-on.
- **Pinnable** as a PyPI pin, both for the plugin (`--with pkg==1.2.3`) and the base (`uv tool install snowflake-cli==3.24.1`).
- **Idempotency is partial**: `uv tool install` needs `--force` or `--reinstall` to redo an existing tool environment. `snow plugin enable` is a config write and is idempotent.

References: [Snowflake CLI docs](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index), [snowflake-cli repository](https://github.com/snowflakedb/snowflake-cli).

## `acli`

No add-on mechanism of any kind. Measured against the binary from `https://acli.atlassian.com/linux/latest/acli_linux_amd64/acli`, the top-level commands are `admin`, `auth`, `confluence`, `guard`, `jira`, `rovodev`, `completion`, `config`, `feedback` and `help` — no `plugin`, `extension` or `components`. Confirmed by the [command reference](https://developer.atlassian.com/cloud/acli/reference/commands/).

It is a single static Go binary, which is also why it has no version pin: the download URL only offers `/latest/`.

The one adjacent form of extensibility is `acli rovodev`, whose beta AI agent supports MCP servers through its own configuration. That is runtime agent configuration, not something installed at setup time.

Reference: [install acli](https://developer.atlassian.com/cloud/acli/guides/install-acli/).

## `kubectl` plugins and krew

- **No apt-level plugin packages.** Measured from the `Packages` file at `https://pkgs.k8s.io/core:/stable:/v1.34/deb/`, the repository ships only `cri-tools`, `kubeadm`, `kubectl`, `kubelet` and `kubernetes-cni`.
- **The mechanism is krew**, which is in no apt repository and installs from a GitHub release tarball. The documented non-interactive bootstrap ([krew setup](https://krew.sigs.k8s.io/docs/user-guide/setup/install/)):

  ```bash
  ( set -x; cd "$(mktemp -d)" &&
    OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
    KREW="krew-${OS}_${ARCH}" &&
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
    tar zxvf "${KREW}.tar.gz" && ./"${KREW}" install krew )
  ```

  krew itself is pinnable by swapping `latest/download` for `download/v0.5.0`.
- **Plugin versions cannot be pinned.** Measured: `krew install --help` offers only `--archive`, `--enable-netrc`, `--manifest` and `--manifest-url`, all marked development-only. There is no `--version`; krew installs whatever the index manifest says at that moment. Reproducibility requires either a custom index pinned to a git revision (`kubectl krew index add <name> <git-url>`) or a self-hosted frozen manifest and tarball passed via `--manifest`/`--archive`.
- **Paths are per-user.** Measured as root: base `/root/.krew`, binaries `/root/.krew/bin`, store `/root/.krew/store`, index `/root/.krew/index/default` from `https://github.com/kubernetes-sigs/krew-index.git`. `KREW_ROOT` overrides the base, and `$KREW_ROOT/bin` must be on `PATH` or the plugins are invisible to `kubectl`.
- **Idempotent**: documented, "If a plugin is already installed, it will be skipped. Failure to install a plugin will not stop the installation of other plugins."
