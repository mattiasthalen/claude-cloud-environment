# AGENTS.md

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `mattiasthalen/claude-cloud-environment` — the repository this line is about, and the one place naming it, since `AGENTS.md` is not shipped. Which surface reaches them is not settled here: `docs/agents/issue-tracker.md` carries the order (`gh` where it is on the PATH, the GitHub MCP tools, then authenticated REST or GraphQL) and is written to name no repository.

### Triage labels

Default five-role vocabulary, with each label string equal to its role name. See `docs/agents/triage-labels.md`.

### Artifacts shipped to provisioned environments

`skills/` holds skills this repo authors and ships into every environment it provisions — currently `skills/swarm/SKILL.md`. `environment.sh` also ships three of this repo's own agent docs — `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md` and `docs/agents/domain.md` — into `~/.claude/docs/agents/`, so a session carries the contract into repositories that keep no copy of it. `docs/agents/testing.md` is not shipped: it describes this repo's own suite. Both kinds are artifacts for the *target* repo, so they bind to no convention local to this one — which is why the tracker doc names no repository.

The shipped docs are a shadowed default, resolved per file: a repo-local `docs/agents/<file>` wins where the repository has one, and the shipped copy applies only where it does not, so a repository holding one of the three takes the other two from the shipped set. `~/.claude/CLAUDE.md` states that rule to every provisioned session, since neither copy can say which is in force. See `docs/adr/0011-the-shipped-agent-docs-are-a-shadowed-default.md`.

### Renaming something the shipped set names

Two clumps of strings are hardcoded across this repo, and neither source file can list the sites that live here — the docs ship into repositories that have none of them, so the list belongs in this file, which is not shipped.

**A triage label string.** `docs/agents/triage-labels.md` is the source table, and the **Ready for work** bullet in `docs/agents/issue-tracker.md` is the other shipped site it names. Three more are authored here: the agent-docs bullet in the `~/.claude/CLAUDE.md` heredoc in `environment.sh`; the fixed-string assertion in `tests/cases/claude-md-shape.sh` that pins that bullet; and the two parking instructions and the worked report in `skills/swarm/SKILL.md`, which name `needs-info` in the prompts a run writes. The skill is the one of the three that ships, so a rename there reaches every provisioned environment at the next release — the same exception the **Ready for work** bullet is.

**One of the three shipped doc filenames** — `issue-tracker.md`, `triage-labels.md`, `domain.md`. A rename visits the file itself under `docs/agents/`, plus: the `AGENT_DOCS` array and the agent-docs bullet in `environment.sh`; `tests/cases/agent-docs-install-at-tag-pin.sh`, `tests/cases/agent-docs-fetch-failure-is-not-fatal.sh` and `tests/cases/agent-docs-name-no-repository.sh`; the "Skills and agent docs" section of `README.md`; the shipped-artifacts paragraph above; and `docs/adr/0011-the-shipped-agent-docs-are-a-shadowed-default.md`. `issue-tracker.md` carries two more, where it is named as a path in the *target* repo: `skills/swarm/SKILL.md` and `docs/adr/0003-a-swarm-run-ships-a-stack-of-pull-requests.md`. Two of the shipped docs also name each other, which is the one class neither of them can list for itself: the **Ready for work** bullet in `docs/agents/issue-tracker.md` names `triage-labels.md`, and the rename paragraph in `docs/agents/triage-labels.md` names `issue-tracker.md`. The rename comment in `tests/cases/claude-md-shape.sh` names `triage-labels.md` too, as the source table it points a reader at.

### Code review

Reviews run through `/code-review`, which spawns one subagent per axis — Standards and Spec — by design, so one axis passing cannot mask the other failing. The fan-out is expected, including in a session carrying a blanket instruction against subagents; provisioned environments say so generally, with a standing request for subagents in `~/.claude/CLAUDE.md` that this review path is one instance of. This line cannot override such an instruction and does not claim to; a session that still cannot run the skill says the review was skipped rather than reporting the work reviewed. `environment.sh` enforces the other half: provisioned environments deny the caveman plugin's `cavecrew-*` subagents and every skill it ships except `caveman`, the level switcher, so `/code-review` is the only review path on offer.

### Tests

`./tests/run.sh` runs the suite: each case invokes `environment.sh` in a fresh Ubuntu 24.04 root container and asserts on its exit code, printed output and container state. Cases are tiered — the `quick` tier gates pull requests, the whole suite runs on a schedule — and `./tests/tiers.test.sh` checks that tiering on the host, with no Docker daemon needed. A hosted web session can run the container suite: `./tests/run.sh` starts `dockerd` itself when none is answering, and Docker Hub is reachable subject to an anonymous rate limit that clears on its own. The PR's `quick` tier remains the gate, because a local run there can be unavailable for reasons unrelated to the change. See `docs/agents/testing.md`.

### Domain docs

`CONTEXT.md` and `docs/adr/` at the repo root, and no `CONTEXT-MAP.md`. `docs/agents/domain.md` carries the consumer rules — how to read those files where they exist — and mandates no layout, so the layout above is this repo's own statement rather than a taxonomy that doc defines.
