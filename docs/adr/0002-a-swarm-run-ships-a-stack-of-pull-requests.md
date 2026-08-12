# A swarm run ships a stack of pull requests, one per ticket

A swarm run used to cut one integration branch, rebase every ticket into it, and leave the human a single pull request for the whole graph — an eighteen-ticket run produced one of +22,140 lines across 47 files, which is not a thing anybody reviews. A run now produces a **stack** instead: each ticket is its own pull request, based on the layer below it, the bottom layer based on the trunk. The agent opens its layer as a draft; the orchestrator reviews the branch, rebases it onto the layer below, and marks it ready. The integration branch is retired — it *was* the giant diff.

## Considered options

**Keep the integration branch as the stack's trunk** was rejected because the stack would then merge into it and a second, equally large pull request would still be needed to reach the default branch. The defect survives the refactor.

**Chain the branches at dispatch time** — each agent cutting from the previous ticket's branch — was rejected because a wave's tickets are dispatched in parallel and their order is not known until their reviews finish. Chaining at dispatch means agents building on unfinished work. The chain is settled at stack time instead, which is the first moment the order exists. The branch an agent *is* cut from is the current top of the stack, so a later wave still inherits everything already stacked — the one job the integration branch did that was worth keeping.

**Gate ready on a clean review** was rejected for the same reason `0001-review-does-not-gate-integration.md` rejected gating integration, plus a new one: a fix agent may legitimately refuse a finding that contradicts the ticket's acceptance criteria, and under a gate that layer would stay a draft with nobody left to unstick it.

**Wait for general availability** was rejected. Stacked pull requests are in public preview, so the skill runs in *chain mode* where the stack API is unavailable: the layers are still cut and still based on each other, and only the stack object is missing. The small diffs are the value; the stack object is navigation.

## Consequences

Swarm now writes to the remote during a run — pushing branches, opening pull requests, force-pushing rebased layers — where before it did everything locally and handed back a branch. It still never merges and never pushes to the trunk.

Tickets no longer close when swarm is done with them; they close when the human merges. That works because each ticket's commits carry `Closes #NN`, and a commit keyword fires whatever the pull request's base branch was, when the commit reaches the default branch — whereas the same keyword in a mid-stack pull request's *body* is ignored, because the body's keywords are only read when the pull request targets the default branch. A repo that allows only squash merges and builds the squash message from the pull request body rewrites those commits and loses the keyword; Preflight reads the repo's merge configuration and the report says so when it applies.

A red or parked ticket keeps its draft pull request out of the stack entirely, based on the trunk. A stack can only be extended at the top and merges atomically downward, so an unready layer in the middle would freeze every layer above it.

Marking a layer ready has no REST endpoint — it is the GraphQL `markPullRequestReadyForReview` mutation, which is what `gh pr ready` calls. So the transport `docs/agents/issue-tracker.md` names has to reach GraphQL, not REST alone; that file describes the transport as "the GitHub REST API" for environments without `gh`, and this is the one operation that wording does not cover.
