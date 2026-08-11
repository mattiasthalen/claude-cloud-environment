---
name: swarm
description: "Implement a parent issue's child tickets, or a named set of tickets, in parallel — one agent per unblocked ticket."
disable-model-invocation: true
---

Take a parent issue with child tickets — or a named set of tickets — and drive the whole graph to done: cut one integration branch, dispatch one isolated agent per unblocked ticket, merge finished work back one at a time, re-query the frontier as tickets unblock, and report state transitions.

Adapted from the proposal by [@berkaykiran](https://github.com/berkaykiran) in [mattpocock/skills#787](https://github.com/mattpocock/skills/issues/787).

## Invocation

```
/swarm #<parent-issue>                    [foreground|background] [model] [effort]
/swarm #<ticket> [& #<ticket> ...]        [foreground|background] [model] [effort]
/swarm                                    [foreground|background] [model] [effort]
```

Every argument after the ticket arguments is optional and positional. Defaults: `background`, this session's model, `normal` effort. Read them from the invocation and proceed on them — swarm settles its own configuration from the command line alone.

Ticket arguments carry the `#` prefix and the trailing arguments do not, which is what keeps `/swarm #46 #47 foreground` readable: every `#`-prefixed token is a ticket, and parsing of the positional arguments starts at the first token without one. A bare number where a ticket is meant (`/swarm 46 47 foreground`) is a stop — say that tickets need the `#` and dispatch nothing, rather than guessing which of `46` and `47` was meant as a model or an effort.

The trailing arguments survive the bare-`/swarm` stop. Mode, model and effort read off a bare invocation are held and applied to whichever run the user then picks, so `/swarm foreground` followed by "build a map" runs that map in the foreground without the user repeating themselves.

- **`foreground`** — dispatch agents synchronously, one wave at a time. Each wave's work is visible in this session and integrates as the wave finishes.
- **`background`** — dispatch agents detached. Integrate each branch as its completion notification arrives.

A mode argument that is neither word is a stop: report the two valid modes and dispatch nothing. Guessing which one the user meant risks running a whole graph in the wrong mode.

### Which ticket set the run drives

The three forms differ only in where the **ticket set** comes from. Everything after Preflight is identical.

- **One issue named** — the ticket set is that issue's open children, per the tracker doc's parent/child convention. This is the normal run.
- **Several tickets named** (`#46 & #47`, `#46 #47`, `#46, #47` — any separator between the `#`-prefixed tokens) — the ticket set is exactly those issues, taken as leaves. Do not look for their children and do not look for a parent. Blocking edges *between* them are still honoured, so a named set can still run in waves. Slug the integration branch from the ticket numbers rather than from a title: `task/issues-46-47`.
- **No ticket named** — a stop. Swarm dispatches nothing until a ticket set exists; see below.

### A bare `/swarm` is a stop that offers to build a map

There is no repo-wide sweep and no guessed parent. A bare `/swarm` runs Preflight steps 1, 2 and 4, then makes two reads — the tracker doc's map convention tells it how a map is marked, so query for existing maps that way, and list the open tickets carrying the ready-for-work label, unassigned and unblocked. Both are reads; neither writes anything. Then it stops and reports:

1. What a run needs: a parent issue with children, or a named set of tickets.
2. The tracker state actually read — that `docs/agents/issue-tracker.md` is present, what those two queries returned: which map issues exist, if any, and how many open tickets carry the repo's ready-for-work label. Take the map convention and the ready-for-work label string from the tracker doc; both are repo-local and neither is ever hardcoded here.
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
> Do not run `/code-review`, and do not report on review at all. A dispatched agent has no `Agent` tool of its own, so the skill's two-axis fan-out has nothing to fan out with. Review is the orchestrator's job and runs before your branch is integrated.
>
> Commit to `issue/NN` with a message referencing #NN, and leave it there — local, unmerged, unpushed. Integration is the orchestrator's job.
>
> **Parking a question:** if a decision is genuinely unsettled — one you'd have to guess at, where a wrong guess means rework — stop implementing, comment the question on #NN, label #NN `needs-info`, and report back that the ticket is parked with the question text. Do not guess.
>
> Report back in one paragraph: landed or parked, what changed, and whether the suite is green. All three elements are required.
>
> Effort: `<effort>`.

Do not call `/implement` — its `disable-model-invocation: true` makes the Skill tool refuse *any* model's call, yours as well as a subagent's, which is why the workflow is inlined above. Only a human typing the command invokes it, so there is no arrangement of this skill that reaches it. Its review half is inlined too, but on the orchestrator's side: an agent dispatched here implements, and step 4 reviews.

### 4. Review, then integrate

Review comes first and reviews run together; integration follows, strictly one at a time.

**Review — run it inline, from this session.** For every agent that reports **landed**, run `/code-review` on `issue/NN` against its merge-base with `task/<slug>` — the commit `issue/NN` was cut from, `git merge-base task/<slug> issue/NN`, not the branch tip. The branch has moved if an earlier ticket of this wave already landed, and reviewing against the tip would pull that ticket's diff into this one's review. Reviewing before the merge means findings land in the ticket's own branch rather than on top of the integration branch.

Run the whole reported batch's reviews together. They read distinct branches and write nothing, so nothing contends; only merges have to be serialised.

Never dispatch an agent to run `/code-review` for you. That agent would have no `Agent` tool of its own, so the skill's two-axis fan-out would die exactly as it does inside an implementing agent. This session is the level the fan-out needs, which is the whole reason review moved here.

**Findings — hand them to a fresh agent.** For each ticket whose review returned findings, dispatch one fix agent into that ticket's own worktree, still checked out on `issue/NN` — both are alive, because nothing has been integrated or removed yet, and the implementing agent is gone. Give the fix agent the same model and effort as the implementing agent had: a finding that took a two-axis review to spot is not a cheaper problem than the code that produced it.

> You are fixing review findings on ticket #NN. Your worktree is `<abs-path>`, already checked out on branch `issue/NN`. Work only there — never `cd` out of it, never touch another worktree, never switch branches.
>
> The findings are below, and so are #NN's acceptance criteria. The criteria are the spec: a fix that violates them is not a fix. Where a finding contradicts the criteria, leave it and say so.
>
> Act on the findings you can, run `<check commands>`, and commit to `issue/NN` with a message referencing #NN. Leave the branch there — local, unmerged, unpushed.
>
> Report back in one paragraph: which findings you fixed, which you left and why, and whether the suite is green.
>
> Findings: `<the review's findings>`. Acceptance criteria: `<the ticket's criteria>`. Effort: `<effort>`.

One pass, no second review — `/implement` reviews once and acts once, and so does this. A finding the fix agent leaves is carried on #NN and in the final report, the same as a finding nobody attempted. A fix agent that comes back red is not a findings problem: that is **Red** below.

**Integrate.** Never two merges in flight. For each reviewed ticket, in completion order:

1. Rebase the ticket branch onto the integration branch, then fast-forward it in:
   `git rebase task/<slug> issue/NN && git merge --ff-only issue/NN`.
2. On conflict, resolve it with `/resolving-merge-conflicts` — during the rebase, so the resolution lands in the ticket's own commits.
3. Run the full check commands on the integration branch.
4. **Green** — keep it. Close #NN per the tracker. Remove the worktree (`git worktree remove`) and delete `issue/NN`. Record the review outcome against the ticket as you close it — *reviewed clean*, *reviewed, findings acted on*, *reviewed, findings open* plus what is open, or *not run* plus the reason.
5. **Red** — the integration branch stays green, always. Fix it in place if the break is small and obviously yours to fix; otherwise `git reset --hard` back to the pre-integration commit, reopen the ticket, comment the failure on #NN, and treat it as parked.

Rebase-and-fast-forward, never `--no-ff`. A merge commit per ticket makes the integration branch un-rebasable, and a repo that allows only rebase merges will refuse the resulting pull request — with the branch's history, not its content, as the reason. The first ticket of a wave fast-forwards on its own; the later ones need the rebase because the branch they were cut from has moved.

Agents that report **parked** are already carrying a `needs-info` comment; leave their branch and worktree in place and move on.

**Review does not gate integration.** Open findings are carried on #NN and in the report, and the ticket still integrates — the work is done and the checks are green. A fix agent that parks on a question changes nothing here either: it too integrates, carrying the question. Ordering the review before the merge buys a cleaner branch, not a veto. Only a red suite gates, and that is the **Red** branch above.

Gating was considered and rejected: the frontier is a dependency graph, so a ticket held back over a finding blocks every ticket that depends on it — and a review finding can be wrong, or can contradict the ticket's own acceptance criteria, while a red suite cannot. The report is what keeps this honest, which is why its open-items block is not optional.

A review that could not run at all leaves the ticket at *not run*, with the reason, and integrates too — it is never silently upgraded to reviewed, and never retried later in the run. This session is already the level that can fan out, so a failure here is the environment's answer, not a scheduling accident.

### 5. Re-query and repeat

After every integration, drop that ticket from the in-flight set and resolve the frontier again — a closed ticket unblocks its dependents. Dispatch the new frontier and loop from step 3. A one-ticket wave is a normal wave: dispatch the one agent and carry on.

The run ends when the frontier is empty **and** the in-flight set is empty. Every remaining open ticket is then either parked on a question or blocked by one that is.

### 6. Report

Hand back the integration branch name, the tickets that landed, the tickets that landed carrying review debt, and the parked batch as plain text:

```
task/<slug> — 6 landed, 2 parked

Landed with open review items:
  #26 — review flagged the duplicated tier table; commented on #26, not fixed
  #28 — /code-review not run: the skill's two-axis fan-out was unavailable in this session

Parked:
  #31 — Should the version constant live in the script or a separate file?
  #34 — Two tickets both claim the verification block; which owns it?
```

One block, two kinds of entry: a ticket that integrated with findings left unfixed, pointing at the comment that carries them, and a ticket whose review could not run, with the reason. They are the same fact to a reader — this ticket merged with review debt — so they are not worth two lists. Omit the block entirely when it has no entries; an absent block means every landed ticket was reviewed and nothing was left open, so it can never be read as silence. Whatever the run also writes — a pull request body above all — carries the same list, in the same words.

Print the questions here as text. Answering them is the user's next move, in their own time — swarm does not wait on them.

## Digest discipline

You are a filter, not a relay. One line per state transition, nothing else:

```
#28 dispatched
#31 dispatched
#28 landed — task/swarm-skill green, reviewed, 2 findings fixed
#31 parked — needs-info
```

A ticket's **landed** line comes after step 4 has reviewed and integrated it, not when the agent reports — the review outcome is part of the line, so the line cannot precede the review. Review, fix agent and merge are steps of your own loop, not states the user steers: they collapse into that one line rather than getting three of their own.

Agent transcripts, diffs, file lists, and progress narration never reach the user. A failure gets one line and its shortest decisive error; the user asks if they want more.
