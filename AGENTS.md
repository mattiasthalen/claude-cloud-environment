# AGENTS.md

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `mattiasthalen/claude-cloud-environment`, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary, with each label string equal to its role name. See `docs/agents/triage-labels.md`.

### Skills shipped to provisioned environments

`skills/` holds skills this repo authors and ships into every environment it provisions — currently `skills/swarm/SKILL.md`. They are artifacts for the *target* repo, so they bind to no convention local to this one.

### Tests

`./tests/run.sh` runs the suite: each case invokes `environment.sh` in a fresh Ubuntu 24.04 root container and asserts on its exit code, printed output and container state. See `docs/agents/testing.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
