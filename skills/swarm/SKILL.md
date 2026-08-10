---
name: swarm
description: "Implement a parent issue's child tickets, or a named set of tickets, in parallel — one agent per unblocked ticket."
disable-model-invocation: true
---

Take a parent issue with child tickets — or a named set of tickets — and drive the whole graph to done: cut one integration branch, dispatch one isolated agent per unblocked ticket, merge finished work back one at a time, re-query the frontier as tickets unblock, and report state transitions.

Adapted from the proposal by [@berkaykiran](https://github.com/berkaykiran) in [mattpocock/skills#787](https://github.com/mattpocock/skills/issues/787).

## Invocation

```
/swarm <parent-issue>                     [foreground|background] [model] [effort]
/swarm <ticket> [& <ticket> ...]          [foreground|background] [model] [effort]
/swarm                                    [foreground|background] [model] [effort]
```

Every argument after the ticket arguments is optional and positional. Defaults: `background`, this session's model, `normal` effort. Read them from the invocation and proceed on them — swarm settles its own configuration from the command line alone.

- **`foreground`** — dispatch agents synchronously, one wave at a time. Each wave's work is visible in this session and integrates as the wave finishes.
- **`background`** — dispatch agents detached. Integrate each branch as its completion notification arrives.

A mode argument that is neither word is a stop: report the two valid modes and dispatch nothing. Guessing which one the user meant risks running a whole graph in the wrong mode.

### Which ticket set the run drives

The three forms differ only in where the **ticket set** comes from. Everything after Preflight is identical.

- **One issue named** — the ticket set is that issue's open children, per the tracker doc's parent/child convention. This is the normal run.
- **Several tickets named** (`#46 & #47`, `#46 #47`, `#46, #47` — any separator) — the ticket set is exactly those issues, taken as leaves. Do not look for their children and do not look for a parent. Blocking edges *between* them are still honoured, so a named set can still run in waves. Slug the integration branch from the ticket numbers rather than from a title: `task/issues-46-47`.
- **No ticket named** — a stop. Swarm dispatches nothing until a ticket set exists; see below.

### A bare `/swarm` is a stop that offers to build a map

There is no repo-wide sweep and no guessed parent. A bare `/swarm` runs Preflight steps 1, 2 and 4, then stops and reports:

1. What a run needs: a parent issue with children, or a named set of tickets.
2. The tracker state actually read — whether `docs/agents/issue-tracker.md` is present, whether a map issue exists, and how many open tickets carry the repo's ready-for-work label. Take the map convention and the ready-for-work label string from the tracker doc; both are repo-local and neither is ever hardcoded here.
3. The two moves on offer, and dispatch nothing until the user picks one:
   - **Run against a named parent** — the user names the issue, and swarm restarts at Preflight step 3.
   - **Build a map and swarm that** — swarm creates a map issue per the tracker doc's map convention, attaches the ready-labelled, unassigned, unblocked open issues to it as children, and adds blocking edges where the work genuinely serialises. Then it runs the normal parent-scoped flow against that map.

Creating a map is a write. It happens only after the user picks it — never speculatively as part of the stop.

A swarm-created map uses the map format the tracker doc defines, and records **why** each blocking edge exists in the map's own prose fields (Notes, or Decisions-so-far) — for example, two tickets editing the same file, serialised to avoid a race. Nothing new is invented for this; the existing map body carries it.

Listing the ready-labelled issues as part of the stop's report is not a dispatch and not a frontier. Swarm computes one frontier and one only, and it is defined in Process step 2.

## Preflight

The frontier is only as good as your reading of the tracker, and a wrong reading dispatches agents at the wrong tickets — the one failure that costs real work rather than a message. So:

1. Read the target repo's `docs/agents/issue-tracker.md`. **If it is absent, stop here.** Report that swarm needs the tracker contract and point the user at `/setup-matt-pocock-skills`. Dispatch nothing.
2. From that file, learn five things and hold them for the whole run: how child tickets hang off a parent, how blocking edges are expressed, how a ticket is claimed and closed, what a map issue looks like, and which label the repo uses for ready-for-work tickets. The last two are only needed by a bare `/swarm`, but they come from the same read.
3. Resolve the ticket set for the invocation's form. With a parent named, fetch the parent and its children through the tracker's own read operations — a parent with no children is a stop: say so and dispatch nothing. With several tickets named, fetch exactly those issues and their blocking edges — one that is closed or missing is a stop: name it and dispatch nothing. With nothing named, take the bare-`/swarm` stop above.
4. Confirm the working tree is clean and note the repo's default branch.

## Process

### 1. Cut the integration branch

`task/<slug>`, cut from the default branch, where `<slug>` derives from the parent issue's title — or, for a named set of tickets with no parent, from the ticket numbers (`task/issues-46-47`). Every ticket branch is cut from it and every merge lands on it. The default branch stays user-controlled — swarm never merges there and never pushes there.

Note the repo's own check commands now — typecheck, test, lint, as its task runner and CI config define them. Every subagent and every integration uses the same ones. A repo with no checks to run is fine; say so once and skip the green gate below.

### 2. Resolve the frontier

The **frontier** is every open ticket in the ticket set whose blockers are all closed, per the blocking semantics the tracker doc defines. Three kinds of ticket are off it: tickets claimed by someone else, tickets swarm has already dispatched and is still waiting on (**in flight**), and tickets parked on a question.

Keep the in-flight set explicitly — in `background` mode agents outlive the wave that dispatched them, and a re-query that forgets them dispatches a second agent at a ticket that already has one.

An empty frontier while nothing is in flight, with open tickets left in the set, means the graph is deadlocked on something outside swarm's reach — report the blocked tickets and their open blockers, and stop.

### 3. Dispatch

One agent per frontier ticket, all dispatched together. For each ticket `NN`, before dispatching:

```bash
git worktree add -b issue/NN ../.swarm/issue-NN task/<slug>
```

Each agent gets its own worktree and its own branch, so no two agents ever share a working tree. Pass the absolute worktree path in the prompt and require the agent to work only inside it. Set the agent's model from the invocation argument; state the effort level in the prompt.

Claim each ticket through the tracker's claim operation as it is dispatched.

**Dispatch prompt** — carry this shape, filled in per ticket:

> You own ticket #NN. Your worktree is `<abs-path>`, already checked out on branch `issue/NN`. Work only there — never `cd` out of it, never touch another worktree, never switch branches.
>
> Read #NN in full, including its comments, using the operations in `docs/agents/issue-tracker.md`. Its acceptance criteria are the spec; implement exactly them.
>
> Use `/tdd` for the behaviour the ticket describes. The ticket's acceptance criteria are the agreed seams — test at those, not at internals. Where the ticket leaves a seam genuinely unsettled, park the question (below) instead of guessing at it.
>
> Run typechecking and the single test file you are working on regularly: `<check commands>`. Run the full suite once at the end.
>
> Then use `/code-review` against `task/<slug>` and act on its findings.
>
> Commit to `issue/NN` with a message referencing #NN, and leave it there — local, unmerged, unpushed. Integration is the orchestrator's job.
>
> **Parking a question:** if a decision is genuinely unsettled — one you'd have to guess at, where a wrong guess means rework — stop implementing, comment the question on #NN, label #NN `needs-info`, and report back that the ticket is parked with the question text. Do not guess.
>
> Report back in one paragraph: landed or parked, what changed, and whether the suite is green.
>
> Effort: `<effort>`.

Do not call `/implement` — its `disable-model-invocation: true` makes the Skill tool refuse a subagent's call, which is why the workflow is inlined above.

### 4. Integrate, one at a time

Never two merges in flight. For each agent that reports **landed**, in completion order:

1. Rebase the ticket branch onto the integration branch, then fast-forward it in:
   `git rebase task/<slug> issue/NN && git merge --ff-only issue/NN`.
2. On conflict, resolve it with `/resolving-merge-conflicts` — during the rebase, so the resolution lands in the ticket's own commits.
3. Run the full check commands on the integration branch.
4. **Green** — keep it. Close #NN per the tracker. Remove the worktree (`git worktree remove`) and delete `issue/NN`.
5. **Red** — the integration branch stays green, always. Fix it in place if the break is small and obviously yours to fix; otherwise `git reset --hard` back to the pre-integration commit, reopen the ticket, comment the failure on #NN, and treat it as parked.

Rebase-and-fast-forward, never `--no-ff`. A merge commit per ticket makes the integration branch un-rebasable, and a repo that allows only rebase merges will refuse the resulting pull request — with the branch's history, not its content, as the reason. The first ticket of a wave fast-forwards on its own; the later ones need the rebase because the branch they were cut from has moved.

Agents that report **parked** are already carrying a `needs-info` comment; leave their branch and worktree in place and move on.

### 5. Re-query and repeat

After every integration, drop that ticket from the in-flight set and resolve the frontier again — a closed ticket unblocks its dependents. Dispatch the new frontier and loop from step 3. A one-ticket wave is a normal wave: dispatch the one agent and carry on.

The run ends when the frontier is empty **and** the in-flight set is empty. Every remaining open ticket is then either parked on a question or blocked by one that is.

### 6. Report

Hand back the integration branch name, the tickets that landed, and the parked batch as plain text:

```
task/<slug> — 6 landed, 2 parked

Parked:
  #31 — Should the version constant live in the script or a separate file?
  #34 — Two tickets both claim the verification block; which owns it?
```

Print the questions here as text. Answering them is the user's next move, in their own time — swarm does not wait on them.

## Digest discipline

You are a filter, not a relay. One line per state transition, nothing else:

```
#28 dispatched
#31 dispatched
#28 landed — task/swarm-skill green
#31 parked — needs-info
```

Agent transcripts, diffs, file lists, and progress narration never reach the user. A failure gets one line and its shortest decisive error; the user asks if they want more.
