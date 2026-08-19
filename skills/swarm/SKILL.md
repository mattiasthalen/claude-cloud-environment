---
name: swarm
description: "Implement a parent issue's child tickets, or a named set of tickets, in parallel — one agent per unblocked ticket, one stacked pull request per ticket."
disable-model-invocation: true
---

Take a parent issue with child tickets — or a named set of tickets — and drive the whole graph to done: dispatch one isolated agent per unblocked ticket, review each finished branch, stack its pull request on the one below, and re-query the frontier as tickets unblock.

The run's product is a **stack**: one pull request per ticket, each **layer** based on the layer below it, the bottom layer based on the **trunk** — the repo's default branch. An agent opens its layer as a draft; swarm marks it **ready** once the branch is reviewed and green. The human reviews layer by layer and merges. Swarm never merges and never pushes to the trunk.

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

- **`foreground`** — dispatch agents synchronously, one wave at a time. Each wave's work is visible in this session and stacks as the wave finishes.
- **`background`** — dispatch agents detached. Stack each layer as its completion notification arrives.

A mode argument that is neither word is a stop: report the two valid modes and dispatch nothing. Guessing which one the user meant risks running a whole graph in the wrong mode.

### Which ticket set the run drives

The three forms differ only in where the **ticket set** comes from. Everything after Preflight is identical.

- **One issue named** — the ticket set is that issue's open children, per the tracker doc's parent/child convention. This is the normal run.
- **Several tickets named** (`#46 & #47`, `#46 #47`, `#46, #47` — any separator between the `#`-prefixed tokens) — the ticket set is exactly those issues, taken as leaves. Do not look for their children and do not look for a parent. Blocking edges *between* them are still honoured, so a named set can still run in waves.
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

Listing the ready-labelled issues as part of the stop's report is not a dispatch and not a frontier. Swarm computes one frontier and one only, and it is defined in Process step 1.

## Preflight

The frontier is only as good as your reading of the tracker, and a wrong reading dispatches agents at the wrong tickets — the one failure that costs real work rather than a message. So:

1. Read the target repo's `docs/agents/issue-tracker.md`. **If it is absent, stop here.** Report that swarm needs the tracker contract and point the user at `/setup-matt-pocock-skills`. Dispatch nothing.
2. From that file, learn five things and hold them for the whole run: how child tickets hang off a parent, how blocking edges are expressed, how a ticket is claimed and closed, what a map issue looks like, and which label the repo uses for ready-for-work tickets. The last two are only needed by a bare `/swarm`, but they come from the same read. The tracker doc also fixes the **transport** — the `gh` CLI where it is on the PATH, the GitHub REST and GraphQL APIs where it is not. Every pull request and stack operation below runs over whichever one the doc names.
3. Resolve the ticket set for the invocation's form. With a parent named, fetch the parent and its children through the tracker's own read operations — a parent with no children is a stop: say so and dispatch nothing. With several tickets named, fetch exactly those issues and their blocking edges — one that is closed or missing is a stop: name it and dispatch nothing. With nothing named, take the bare-`/swarm` stop above.
4. Confirm the working tree is clean and note the trunk.
5. Note the repo's own check commands — typecheck, test, lint, as its task runner and CI config define them. Every subagent, every review and every layer uses the same ones. A repo with no checks to run is fine; say so once and skip every green gate below.
6. Read the repo's merge configuration (`GET /repos/{owner}/{repo}`) and hold `allow_squash_merge`, `allow_rebase_merge`, `allow_merge_commit` and `squash_merge_commit_message`. A repo that allows **only** squash merges, with the squash message set to the pull request's title and body, rewrites commit messages on merge and drops the `Closes #NN` that each ticket relies on. Where that holds, say so once in the report: those tickets need closing by hand.
7. Establish whether the stack API is available: `GET /repos/{owner}/{repo}/stacks`. A `200` means stacks are live for this repo. Anything else means **chain mode** — layers are still cut and still based on each other, so the diffs stay small, but no stack object is created and the human merges bottom-up rather than in one operation. Hold which mode the run is in; the report states it once. Stacked pull requests are in public preview and require every branch to live in this repo.

## Process

### 1. Resolve the frontier

The **frontier** is every open ticket in the ticket set whose blockers are all satisfied. Read the blocking edges the way the tracker doc defines them, then apply one rule the doc does not know about: a blocker this run has already stacked counts as satisfied, even though it is still open.

That override is load-bearing, and swarm owns it rather than the tracker doc. The doc's own test is closure — its frontier query drops any ticket with an open blocker — and a ticket now closes when a human merges the stack, long after the run has ended. Without the override a run would stall after its first wave, every dependent still reading as blocked. So hold the **stacked set** explicitly, alongside the in-flight set, for the whole run.

Three kinds of ticket are off the frontier: tickets claimed by someone else, tickets swarm has already dispatched and is still waiting on (**in flight**), and tickets parked on a question.

Keep the in-flight set explicitly — in `background` mode agents outlive the wave that dispatched them, and a re-query that forgets them dispatches a second agent at a ticket that already has one.

An empty frontier while nothing is in flight, with open tickets left in the set, means the graph is deadlocked on something outside swarm's reach. Two comments close that out, and both are needed:

- **On each undispatched ticket** — name the open blocker and say the run ended without dispatching it. A ticket that never ran carries no other trace: the blocking edge says it is blocked, and only the comment says its blocker died.
- **On the blocker** — append the tickets it is holding up to the park or failure comment it already carries, rather than adding a second comment. Whoever answers that question is reading that comment, and the cost of leaving it unanswered belongs in it.

Then report them and stop.

### 2. Dispatch

One agent per frontier ticket, all dispatched together. For each ticket `NN`, before dispatching:

```bash
git worktree add -b issue/NN ../.swarm/issue-NN <base>
```

`<base>` is the head branch of the **topmost layer in the stack**, or the trunk while the stack is empty. That is how a later wave inherits every ticket already stacked, and it is what makes the stack physical rather than bookkeeping. Agents in one wave share a base and are siblings; their order within the stack is settled in step 4, when it is first known.

Each agent gets its own worktree and its own branch, so no two agents ever share a working tree. Pass the absolute worktree path in the prompt and require the agent to work only inside it. Set the agent's model from the invocation argument; state the effort level in the prompt.

Claim each ticket through the tracker's claim operation as it is dispatched.

**Dispatch prompt** — carry this shape, filled in per ticket:

> You own ticket #NN. Your worktree is `<abs-path>`, already checked out on branch `issue/NN`, cut from `<base>`. Work only there — never `cd` out of it, never touch another worktree, never switch branches.
>
> Read #NN in full, including its comments, using the operations in `docs/agents/issue-tracker.md`. Its acceptance criteria are the spec; implement exactly them.
>
> Use `/tdd` for the behaviour the ticket describes. The ticket's acceptance criteria are the agreed seams — test at those, not at internals. Where the ticket leaves a seam genuinely unsettled, park the question (below) instead of guessing at it.
>
> Run typechecking and the single test file you are working on regularly: `<check commands>`. Run the full suite once at the end.
>
> Do not run `/code-review`, and do not report on review at all. A dispatched agent has no `Agent` tool of its own, so the skill's two-axis fan-out has nothing to fan out with. Review is the orchestrator's job and runs before your layer is stacked.
>
> Commit to `issue/NN`. **At least one commit message must contain `Closes #NN`** — that keyword is what closes the ticket when the stack lands on the trunk, and it works from the commit whatever the layer's base branch is.
>
> Then push `issue/NN` and open a **draft** pull request against `<base>`, through the transport `docs/agents/issue-tracker.md` names. Title it from the ticket; write the body as what changed and why, and end it with `Closes #NN`. Leave it as a draft — the orchestrator reviews it, stacks it, and marks it ready.
>
> **Parking a question:** if a decision is genuinely unsettled — one you'd have to guess at, where a wrong guess means rework — stop implementing, comment the question on #NN, label #NN `needs-info`, and report back that the ticket is parked with the question text. Do not guess.
>
> **A missing dependency is a fact, not a question.** If #NN turns out to need code from another ticket that is still open, record it: add the blocking edge on the tracker, per `docs/agents/issue-tracker.md`, then stop and report that you did. That is a different move from parking — it needs no human answer, and the orchestrator's next frontier query picks #NN up once the blocker lands.
>
> Report back in one paragraph: landed, parked, or blocked on a dependency you recorded; what changed; your pull request's number; and whether the suite is green. All four elements are required.
>
> Effort: `<effort>`.

Do not call `/implement` — its `disable-model-invocation: true` makes the Skill tool refuse *any* model's call, yours as well as a subagent's, which is why the workflow is inlined above. Only a human typing the command invokes it, so there is no arrangement of this skill that reaches it.

### 3. Review, then fix

Review comes first and reviews run together; stacking follows, strictly one at a time.

**Review — run it inline, from this session.** For every agent that reports **landed**, run `/code-review` on `issue/NN` against `git merge-base <base> issue/NN` — the commit the branch was cut from, not the base's tip, which has moved if an earlier ticket of this wave has already stacked. Reviewing at the merge-base runs the moment the agent reports, without waiting on the wave's order, and once the branch is rebased in step 4 that diff and the pull request's own diff are the same commits.

Run every reported ticket's review together. They read distinct branches and write nothing, so nothing contends.

Never dispatch an agent to run `/code-review` for you. That agent would have no `Agent` tool of its own, so the skill's two-axis fan-out would die exactly as it does inside an implementing agent. This session is the level the fan-out needs, which is the whole reason review lives here.

**Findings — hand them to a fresh agent.** For each ticket whose review returned findings, dispatch one fix agent into that ticket's own worktree, still checked out on `issue/NN` — both are alive, because nothing has been rebased or removed yet, and the implementing agent is gone. Give the fix agent the same model and effort as the implementing agent had: a finding that took a two-axis review to spot is not a cheaper problem than the code that produced it.

> You are fixing review findings on ticket #NN. Your worktree is `<abs-path>`, already checked out on branch `issue/NN`. Work only there — never `cd` out of it, never touch another worktree, never switch branches.
>
> The findings are below, and so are #NN's acceptance criteria. The criteria are the spec: a fix that violates them is not a fix. Where a finding contradicts the criteria, leave it and say so.
>
> Act on the findings you can, run `<check commands>`, and commit to `issue/NN`. Push the branch when you are done; its pull request updates itself. Leave it as a draft.
>
> **Parking a finding:** where acting on one would mean guessing at an unsettled decision, stop, comment the question on #NN, label #NN `needs-info`, and report the finding as parked with the question text. Do not guess.
>
> Report back in one paragraph: which findings you fixed, which you left or parked and why, and whether the suite is green.
>
> Findings: `<the review's findings>`. Acceptance criteria: `<the ticket's criteria>`. Effort: `<effort>`.

One pass, and the fix agent's work is not reviewed again. A review-fix-review loop has no natural stopping point, and the layer is now a small pull request a human reads before merging — the second opinion is theirs, and it is a better one. A finding the fix agent leaves or parks is carried on #NN and in the final report, and the layer stacks regardless.

### 4. Stack the layer

Never two at once. For each ticket whose review is done and whose suite is green, in the order the reviews finished — `<base>` here is the current top layer's head branch, or the trunk while the stack is empty:

1. `git rebase <base> issue/NN`. On conflict, resolve it with `/resolving-merge-conflicts` during the rebase, so the resolution lands in the ticket's own commits.
2. Run the full check commands on the rebased branch. Red is the one case that stops a ticket — see below.
3. `git push --force-with-lease` the rebased branch. Force-push only branches this run created; a branch a human has pushed to is a stop, reported and left alone.
4. Retarget the ticket's pull request to `<base>`, so its base ref is the head of the layer below and its diff shows only this ticket's commits.
5. Extend the stack: `POST /repos/{owner}/{repo}/stacks` with the ordered `pull_requests` array for the first layer, `POST /repos/{owner}/{repo}/stacks/{stack_number}/add` for every layer after. Chain mode skips this step and nothing else.
6. Mark the pull request ready for review. There is no REST endpoint for this — it is the GraphQL `markPullRequestReadyForReview` mutation, which is what `gh pr ready` calls.
7. Comment the pull request's URL on #NN and leave the ticket open. A mid-stack pull request's base is not the trunk, so the `Closes #NN` in its body is inert; the keyword in its commits is what closes the ticket, when the stack lands. Until then the comment is the only thing pointing at the work.
8. Remove the worktree (`git worktree remove`) and **keep `issue/NN`** — the pull request is served by that branch until a human merges it.

Rebase and force-push, never a merge commit. A merge commit per ticket makes the layer un-rebasable, and a stack must have fully linear history between its branches or GitHub refuses to merge it until the stack is rebased.

**Review does not gate ready.** Open findings are carried on #NN and in the report, and the layer is still marked ready — the work is done and the checks are green. A fix agent that parks on a question changes nothing here either: its layer stacks too, carrying the question. Draft-to-ready means *swarm is finished with this layer*, not *review approved it*; the approval is the human's, and giving them small layers to approve is the point. Only a red suite gates.

**Red, or parked.** A ticket whose fix agent comes back red, whose rebase leaves the suite red, or whose agent parked on a question does not join the stack. Its pull request stays a draft based on the trunk, carrying the failure or the question as a comment on #NN, and the next healthy ticket stacks onto the last good layer. Keep the branch and the worktree in place. This is deliberate: a stack can only be added to at the top and merges atomically downward, so an unready layer in the middle would freeze every layer above it, and one bad ticket would cost the run its whole merge.

### 5. Re-query and repeat

After every layer, drop that ticket from the in-flight set, add it to the stacked set, and resolve the frontier again — a stacked blocker unblocks its dependents. Dispatch the new frontier and loop from step 2. A one-ticket wave is a normal wave.

An agent that came back having recorded a blocking edge leaves the in-flight set too, and joins neither the stacked set nor the parked ones. Its ticket is simply blocked now, and the edge it wrote is what returns it to the frontier once its blocker stacks.

The run ends when the frontier is empty **and** the in-flight set is empty. Every remaining open ticket is then either parked on a question or blocked by one that is.

### 6. Stack review

The per-layer review of step 3 reads one ticket against one ticket's acceptance criteria. Two classes of finding are invisible to it and visible only here: a requirement of the parent spec that no child ticket claimed, and two layers that duplicate or contradict each other. When the parent issue *is* a specification, that first class is the one that matters — the stack can be six green layers and still not be the thing the spec asked for.

So once the run has ended — frontier empty, in-flight set empty — review the stack as one diff, once, inline from this session for step 3's reason.

Skip it in exactly two cases, and say which in the report: **nothing stacked**, or **one layer stacked** — a one-layer stack is the diff step 3 already reviewed, and reviewing it twice buys nothing.

1. Run `/code-review` over `<trunk>...<top-layer-branch>` — the trunk as the fixed point, the top layer's head as the target. Every layer is rebased onto the layer below and the bottom onto the trunk, so that diff is the run's whole product and nothing else. Give both axes that ref pair as the diff command outright, in place of the skill's `...HEAD` default: its sub-agents run their own `git diff` in this session's working tree, which is on none of the layer branches. Nothing is checked out and no worktree is cut.
2. Name the **parent issue** as the spec explicitly, ahead of the `Closes #NN` refs the skill would otherwise resolve — those name the children, and the parent is the one document no per-layer review ever read. Pass the child tickets alongside it, and say which of them are parked or red: their work is not in this diff, so their requirements would otherwise read as gaps in the parent's coverage. For a named set with no parent, tell the skill there is no spec, so the Spec axis skips rather than stopping to ask for one. The Standards axis needs nothing extra.

**Findings here are reported, never fixed.** A fix at this level lands in one layer and forces a rebase of every layer above it, on a stack the human may already be reading — see `0009-the-stack-gets-one-review-of-its-own.md`. So: comment each finding on the pull request of the layer it belongs to, comment the ones that belong to no single layer on the parent issue, and carry all of them in the report. Nothing is re-stacked and no layer's ready state changes.

A stack review that cannot run leaves the run at *stack review not run*, with the reason, exactly as a per-layer review does. Never retry it and never report the stack as reviewed.

### 7. Report

Write the report as a comment on the parent issue — or, for a named set with no parent, on the bottom layer's pull request. It has to outlive the session, and the parked and blocked entries are the part that has to be found again:

```
Stack #7 — 6 layers ready, 2 parked

Ready with open review items:
  #26 — review flagged the duplicated tier table; commented on #26, not fixed
  #28 — /code-review not run: the skill's two-axis fan-out was unavailable in this session

Parked:
  #31 — Should the version constant live in the script or a separate file?
  #34 — Two tickets both claim the verification block; which owns it?

Not dispatched:
  #35 — blocked by #31, which parked

Stack review (6 layers against #25):
  Spec — #25's "every provisioned environment logs the pin it resolved" is in no layer; commented on #25
  Standards — the tier table is duplicated across layers 3 and 5; commented on the layer 5 pull request

Every ticket closes when the stack merges. Merge from the top layer down.
```

One block, two kinds of entry, for layers that shipped with review debt: a layer that stacked with findings left unfixed, pointing at the comment that carries them, and a layer whose review could not run, with the reason. They are the same fact to a reader. Omit a block entirely when it has no entries; an absent block means every ready layer was reviewed and nothing was left open, so it can never be read as silence.

A review that could not run at all leaves the ticket at *not run*, with the reason, and its layer stacks too — never silently upgraded to reviewed, and never retried later in the run. This session is already the level that can fan out, so a failure here is the environment's answer, not a scheduling accident.

The **stack review** block carries the stack review's findings, per axis, each with the comment it was left on — and it is the one block that is never silently absent. A run that skipped the stack review says so on that line instead (`skipped — one layer stacked`, `not run — <reason>`), because "no cross-layer findings" and "nobody looked across the layers" are opposite facts.

Where Preflight found a squash-only repo that rewrites commit messages, or chain mode, say so here in one line each. Print the parked questions as text. Answering them is the user's next move, in their own time — swarm does not wait on them.

## Digest discipline

You are a filter, not a relay. One line per state transition, nothing else:

```
#29 dispatched
#31 dispatched
#29 ready — layer 3, reviewed, 2 findings fixed
#31 parked — needs-info, out of the stack
#33 blocked — recorded an edge on #29, back to the frontier next wave
stack reviewed — 6 layers, 2 findings, commented
```

A ticket's **ready** line comes after step 4 has reviewed, rebased and stacked it, not when the agent reports — the review outcome is part of the line, so the line cannot precede the review. Review, fix agent, rebase and stack are steps of your own loop, not states the user steers: they collapse into that one line rather than getting four of their own.

Agent transcripts, diffs, file lists, and progress narration never reach the user. A failure gets one line and its shortest decisive error; the user asks if they want more.
