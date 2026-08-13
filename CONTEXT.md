# Claude Cloud Environment

This repo provisions Claude Code cloud environments, and authors the agent skills those environments ship with. Its language is therefore two-sided: the box being built, and the runs that happen inside it.

## Language

### Swarm runs

**Ticket set**:
The issues a single swarm run drives — a parent issue's open children, or an explicitly named group of issues.
_Avoid_: batch, backlog

**Frontier**:
The tickets in the ticket set that can be dispatched right now: open, unclaimed, not in flight, not parked, and with every blocker closed or already stacked.
_Avoid_: queue, ready set, next up

**In flight**:
A ticket swarm has dispatched an agent at and has not yet reviewed.

**Parked**:
A ticket an agent stopped on because a decision was genuinely unsettled. It carries the question as a comment and waits on a human.
_Avoid_: blocked, stuck, deferred — *blocked* is the distinct case of a ticket whose blocker is open.

**Stack**:
The pull requests one swarm run produces, ordered bottom to top, each based on the one below it. The unit the human reviews and merges.
_Avoid_: chain (reserved for chain mode), series, train

**Layer**:
One ticket's pull request, considered as its position in a stack.
_Avoid_: step, level, node

**Trunk**:
The branch the bottom layer is based on — the repo's default branch.
_Avoid_: base branch (ambiguous: every layer has a base), main, master

**Integration branch**:
Retired. The single branch a swarm run once rebased every ticket into, and the one pull request that carried the lot. A run ships a stack now; nothing plays this role.
_Avoid_: `task/<slug>`, integration branch — both name a thing that no longer exists.

**Chain mode**:
A run where the stack API is unavailable, so layers are still based on each other but no stack object exists and the human merges bottom-up.

**Ready**:
The state of a layer swarm has finished with: reviewed, rebased onto the layer below, green, and no longer a draft. Not a claim that review found nothing.
_Avoid_: approved, done, complete

### Provisioning

**Selectable tool**:
A CLI a caller can ask `environment.sh` to install, named as an argument to the script.

**Requested tool**:
A selectable tool an environment actually named on its setup line. Nothing the script installs or configures happens except in response to one.
_Avoid_: enabled tool, chosen tool

**Presence guard**:
The check that skips work for a tool already on `PATH`. It is what makes a second run over the same container a no-op, and it deliberately ignores the installed version rather than self-healing a wrong one.
_Avoid_: idempotency check, install guard

**Addon**:
A selectable tool that installs into a parent tool rather than standing alone, and fails without it.

**Pin**:
The version a tool installs at, asserted after install so a silent version drift fails the run. Exact for every tool whose upstream lets it be — `git-lfs` pins a release series instead, because the Ubuntu archive supersedes the revision below it in place.

**Tier**:
The band a test case belongs to, deciding which runs execute it.

### Git LFS

**Pointer file**:
The few-hundred-byte stand-in Git stores in place of an LFS-tracked file's real content. A clone with no LFS filters registered leaves these in the working tree, where anything reading one fails with an error naming neither LFS nor the cause.
_Avoid_: stub, placeholder, LFS file

**LFS filters**:
The smudge/clean pair that swaps pointer files for real blobs on checkout and back again on commit. Registered system-wide in the snapshot, so a session's later clone brings down real blobs with no further step.
_Avoid_: LFS hooks, LFS config

### Hosted sessions

**Agent proxy**:
The outbound HTTPS proxy every hosted session's traffic passes through, and the source of part of the environment that session is handed.
_Avoid_: egress proxy, network proxy

**Injected variable**:
An environment variable the agent proxy places in every session, whether or not anything in that session can use it.
_Avoid_: provided variable, ambient variable

**Blocking ask**:
A question a session puts to its user in prose at the end of a turn, halting the run until it is answered. Distinct from **Parked**: a parked ticket carries its question durably as a comment and the run continues elsewhere, whereas a blocking ask exists only in a transcript nobody may be watching.
_Avoid_: prompt, interrupt, user question

**Session shell**:
A shell a session's own tooling starts, as opposed to one `environment.sh` starts. Login and interactive non-login session shells read different startup files, so anything written for them has to name both.
_Avoid_: user shell, terminal
