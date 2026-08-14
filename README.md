# claude-cloud-environment

`environment.sh` is the setup script for Claude Code on the web environments. It
installs the Claude plugins and settings, plus exactly the command-line tools an
environment asks for, at pinned versions, and fails the run if anything did not
land.

## The box

Each environment's setup-script box is one line: fetch the script at an
immutable tag and pipe it into `bash`, listing the tools that environment needs
as positional arguments.

```
# environment.sh v1.10.0
curl -sL https://raw.githubusercontent.com/mattiasthalen/claude-cloud-environment/refs/tags/v1.10.0/environment.sh | bash -s -- gcloud kubectl gke-gcloud-auth-plugin snow
```

The tag is what makes the box a decision: a change reaches an environment only
when someone deliberately edits the box. `main` is deployed nowhere; only tags
are. Use the full `vMAJOR.MINOR.PATCH` form — a truncated `v1` or `v1.0` would
be a moving target and is not a release tag here.

The argument list is the complete manifest of what gets installed. Valid names
are the binary names: `gcloud`, `az`, `kubectl`, `snow`, `prefect`, `acli`,
`kubelogin`, `newrelic`, `helm`, `git-lfs`, and the add-on
`gke-gcloud-auth-plugin` (which requires `gcloud` in the same list).
An unknown name fails before anything is installed. No arguments is a valid
invocation and installs the plugins and settings only.

`git-lfs` is worth naming for an environment whose repositories keep binaries in
Git LFS. Without it a session's clone brings those files down as pointer files a
few hundred bytes long, and whatever tries to read one fails with an error that
mentions neither LFS nor the cause. Requesting it registers the LFS filters
system-wide in the snapshot, so clones — which happen after the snapshot is
restored — bring down the real blobs with no further step.

## Skills

`skills/` holds the skills this repo ships into every environment — currently
`swarm`, adapted from [@berkaykiran](https://github.com/berkaykiran)'s proposal
in [mattpocock/skills#787](https://github.com/mattpocock/skills/issues/787). The
script fetches each one into `~/.claude/skills/` from the same immutable tag it
was itself fetched at, so a box pinned to a tag gets the skills that shipped
with that tag.

Skills are always installed and are not names the argument list accepts: that
list exists because CLIs are heavy and differ per environment, and a Markdown
file is neither. A fetch that fails costs one absent slash command and is
reported in the recap; it does not abort the rest of the setup.

**Which tools an environment uses lives only in that environment's box.** This
repo keeps no table of who requested what; reading a box is the only way to know
what that environment gets, and the box is the only place to change it.

## Prerequisites

- The environment runs the **`Full` network access level**. The script fetches
  from vendor apt repositories, PyPI, GitHub and vendors' own download hosts,
  and cannot check or influence
  an environment-level setting; on a restricted level the failure presents as an
  ordinary download failure.
- Authentication is the box's business, not this script's. **No client names and
  no credentials belong in this repo** — it is public, and neither project IDs,
  subscriptions, accounts nor warehouses may leak into it.

## Versioning and rolling

`SCRIPT_VERSION` at the top of `environment.sh` is the single source of truth,
and the script echoes it as its first line of output, so a container-start log
always says which snapshot ran.

What a bump means when planning a roll across environments:

| Bump | Meaning | Effect on a box |
| --- | --- | --- |
| MAJOR | The invocation itself changed — a renamed or removed tool name, or a change in how arguments are read. | The box text must be rewritten, not just re-tagged. |
| MINOR | A new capability, such as an additional tool that can be requested, a shipped skill, or a new standing rule in the memory file every session reads. | Existing box text stays valid; re-tag to pick the change up. |
| PATCH | A pin bump or a fix. | Existing box text stays valid; re-tag to pick the change up. |

Every change a provisioned session can observe warrants a bump — a tool, a pin,
a shipped skill, or the prose written into `~/.claude/CLAUDE.md`. The tag is the
only thing that refreshes an environment, so a change that lands without one
reaches no box, however small it looked in review.

Environments may sit on different tags during a roll. Rolling one environment
first to prove a change and leaving the rest behind is expected — convergence is
the norm and divergence a transient state, and neither is enforced anywhere.

## Releasing

Bumping `SCRIPT_VERSION` and pushing to `main` *is* the release. Continuous
delivery reads the constant and, when no tag of that name exists, creates
`vMAJOR.MINOR.PATCH` at that commit and a GitHub Release whose body is the bump
commit's message with GitHub's generated notes appended — so the Release itself
says whether a roll is urgent or can wait.

- A push that leaves `SCRIPT_VERSION` unchanged produces no tag and no release,
  and does not fail.
- A version whose tag already exists is a silent skip.
- A non-increasing version fails the workflow, using the same check
  (`scripts/check-version.sh`) that guards pull requests.

There is no `CHANGELOG.md`. The tags, the Releases and the commit messages are
the record.
