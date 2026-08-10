# AGENTS.md

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `mattiasthalen/claude-cloud-environment`, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary, with each label string equal to its role name. See `docs/agents/triage-labels.md`.

### Skills shipped to provisioned environments

`skills/` holds skills this repo authors and ships into every environment it provisions — currently `skills/swarm/SKILL.md`. They are artifacts for the *target* repo, so they bind to no convention local to this one.

### Code review

Reviews run through `/code-review`, which spawns one subagent per axis — Standards and Spec — by design, so one axis passing cannot mask the other failing. The fan-out is expected, including in a session carrying a blanket instruction against subagents. This line cannot override such an instruction and does not claim to; a session that still cannot run the skill says the review was skipped rather than reporting the work reviewed. `environment.sh` enforces the other half: provisioned environments deny the caveman plugin's `cavecrew-*` subagents and every skill it ships except `caveman`, the level switcher, so `/code-review` is the only review path on offer.

### Tests

`./tests/run.sh` runs the suite: each case invokes `environment.sh` in a fresh Ubuntu 24.04 root container and asserts on its exit code, printed output and container state. Cases are tiered — the `quick` tier gates pull requests, the whole suite runs on a schedule — and `./tests/tiers.test.sh` checks that tiering on the host, with no Docker daemon needed. A hosted web session cannot run the container suite at all — no daemon, and no Docker Hub access to give it one — so there the gate is `bash -n environment.sh`, `./tests/tiers.test.sh`, `./tests/check-version.test.sh` plus the PR's `quick` tier. See `docs/agents/testing.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
