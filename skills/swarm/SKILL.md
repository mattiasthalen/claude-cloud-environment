---
name: swarm
description: "Implement a parent issue's child tickets in parallel, one agent per unblocked ticket."
disable-model-invocation: true
---

Take a parent issue with child tickets and drive the whole graph to done: cut one integration branch, dispatch one isolated agent per unblocked ticket, merge finished work back one at a time, re-query the frontier as tickets unblock, and report state transitions.

Adapted from the proposal by [@berkaykiran](https://github.com/berkaykiran) in [mattpocock/skills#787](https://github.com/mattpocock/skills/issues/787).

## Invocation

```
/swarm <parent-issue> [foreground|background] [model] [effort]
```

Every argument after the parent is optional and positional. Defaults: `background`, this session's model, `normal` effort. Read all four from the invocation and proceed on them — swarm settles its own configuration from the command line alone.

- **`foreground`** — dispatch agents synchronously, one wave at a time. Each wave's work is visible in this session and integrates as the wave finishes.
- **`background`** — dispatch agents detached. Integrate each branch as its completion notification arrives.

A mode argument that is neither word is a stop: report the two valid modes and dispatch nothing. Guessing which one the user meant risks running a whole graph in the wrong mode.

## Preflight

The frontier is only as good as your reading of the tracker, and a wrong reading dispatches agents at the wrong tickets — the one failure that costs real work rather than a message. So:

1. Read the target repo's `docs/agents/issue-tracker.md`. **If it is absent, stop here.** Report that swarm needs the tracker contract and point the user at `/setup-matt-pocock-skills`. Dispatch nothing.
2. From that file, learn three things and hold them for the whole run: how child tickets hang off a parent, how blocking edges are expressed, and how a ticket is claimed and closed.
3. Fetch the parent issue and its children through the tracker's own read operations. A parent with no children is a stop: say so and dispatch nothing.
4. Confirm the working tree is clean and note the repo's default branch.

## Process

### 1. Cut the integration branch

`task/<slug>`, cut from the default branch, where `<slug>` derives from the parent issue's title. Every ticket branch is cut from it and every merge lands on it. The default branch stays user-controlled — swarm never merges there and never pushes there.

Note the repo's own check commands now — typecheck, test, lint, as its task runner and CI config define them. Every subagent and every integration uses the same ones. A repo with no checks to run is fine; say so once and skip the green gate below.

### 2. Resolve the frontier

The **frontier** is every open child ticket whose blockers are all closed, per the blocking semantics the tracker doc defines. Three kinds of ticket are off it: tickets claimed by someone else, tickets swarm has already dispatched and is still waiting on (**in flight**), and tickets parked on a question.

Keep the in-flight set explicitly — in `background` mode agents outlive the wave that dispatched them, and a re-query that forgets them dispatches a second agent at a ticket that already has one.

An empty frontier while nothing is in flight, with open children left, means the graph is deadlocked on something outside swarm's reach — report the blocked tickets and their open blockers, and stop.

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

1. `git merge --no-ff issue/NN` onto `task/<slug>`.
2. On conflict, resolve it with `/resolving-merge-conflicts`.
3. Run the full check commands on the integration branch.
4. **Green** — keep it. Close #NN per the tracker. Remove the worktree (`git worktree remove`) and delete `issue/NN`.
5. **Red** — the integration branch stays green, always. Fix it in place if the break is small and obviously yours to fix; otherwise `git reset --hard` back to the pre-merge commit, reopen the ticket, comment the failure on #NN, and treat it as parked.

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
