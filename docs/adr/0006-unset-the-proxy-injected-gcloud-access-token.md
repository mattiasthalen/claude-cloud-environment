# Unset the proxy-injected gcloud access token in session shells

Status: accepted (2026-08-12) — issue #56, implemented in PR #60.

The agent proxy injects `CLOUDSDK_AUTH_ACCESS_TOKEN` into every hosted session,
carrying a token Google rejects: with it set, `gcloud` fails with
`ACCESS_TOKEN_TYPE_UNSUPPORTED` or reports no active account no matter what
credentials the session itself holds. `gcloud` reads the variable from the
environment on every invocation and no config key overrides it, so the only fix
is to take it out of the environment. We do that from the shell startup files —
a snippet in `/etc/profile.d` for login session shells, sourced from
`/etc/bash.bashrc` for interactive non-login ones — and only when the selection
includes `gcloud` or `gke-gcloud-auth-plugin`.

## Considered options

**A wrapper on `PATH`** — a shim at `/usr/local/bin/gcloud` that unsets the
variable and `exec`s the real binary — would cover every caller regardless of
shell type, including a bare non-interactive `bash -c`. It was rejected because
the coverage it buys is coverage nothing here needs: a session's tooling starts
shells that read the profile. The costs are real — one shim per SDK entrypoint
(`gcloud`, `gsutil`, `bq`, `gke-gcloud-auth-plugin`), a shadowed vendor binary
that anyone calling `/usr/bin/gcloud` by absolute path escapes anyway, and a
collision with the presence guard, which decides by `PATH` lookup and would then
be answering a question about our own shim.

**Writing the unset unconditionally**, rather than gating it, was rejected to
keep the script's opt-in model intact: every other action it takes follows from
a requested tool, and this would otherwise be its first unconditional write to a
machine's shell startup files. The gate names `gke-gcloud-auth-plugin` as well
as `gcloud` because that plugin is separately requestable and ships in the same
SDK, so a selection carrying it without `gcloud` is legal and untested. Whether
the plugin reads this variable at all is unverified — it is a Go binary, while
`CLOUDSDK_AUTH_ACCESS_TOKEN` maps to the Python CLI's `auth/access_token`
property, so it may well ignore it. The wider gate is chosen on the asymmetry
rather than on evidence: naming a tool that turns out not to need the unset
costs one harmless `unset` of a variable nothing else reads, while omitting a
tool that does need it costs a silent auth failure.

## Consequences

A bare non-interactive `bash -c` reads neither startup file and keeps the broken
token. Reaching it would mean pointing `BASH_ENV` at a file, which puts this
script in the path of every non-interactive shell in the container for one
variable's sake — not a trade we make, so the gap is documented instead.

Only the token is removed. The `CLOUDSDK_PROXY_TYPE`, `CLOUDSDK_PROXY_ADDRESS`,
`CLOUDSDK_PROXY_PORT` and `CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE` variables
injected alongside it are what route `gcloud` through the agent proxy and make
it trust that proxy's CA; unsetting them would trade a broken auth path for a
broken network path.

Removing the variable from the shell, rather than from one command, means every
Cloud SDK entrypoint in that shell — `gsutil` and `bq` as much as `gcloud` — is
covered by the same write.

Nothing removes the snippet if a later run's selection drops both tools. The
script has no removal path for anything else it installs, and containers start
from a clean base, so a stale snippet needs a persisted box to exist at all.
