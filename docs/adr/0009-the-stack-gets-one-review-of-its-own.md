# The stack gets one review of its own

A swarm run reviewed each layer as it was cut — one ticket's diff against one ticket's acceptance criteria — and then reported. Nothing ever read the stack whole. Two classes of defect survive that: a requirement the parent spec asked for that no child ticket claimed, and two layers that duplicate or contradict each other. Neither is visible from inside a single layer, because each layer is faithful to its own ticket. When the parent issue is a specification rather than a container, the first class is the expensive one — six green layers that are not the thing the spec asked for.

So a run now ends with one `/code-review` of the whole stack: the trunk as the fixed point, the top layer's head as the target, and the parent issue named to the Spec axis as the spec — ahead of the `Closes #NN` refs in the commits, which name the children. It runs inline from the orchestrating session, like the per-layer reviews and for the same reason — the two-axis fan-out needs the `Agent` tool a dispatched agent does not have.

## Considered options

**Leave it to the per-layer reviews** was rejected: they are scoped to a ticket by construction, and the parent spec is not an input to any of them. Widening a layer's review to the parent spec would flag every requirement the *other* layers own, on every layer.

**Fix the findings** was rejected. A fix at stack level lands in one layer and forces a rebase of every layer above it, re-running each layer's checks, on a stack the human may already be reading — the whole stack spent on a finding they can act on from one comment. Findings are commented on the layer they belong to, or on the parent issue where they belong to no single layer, and carried in the report. This is `0001-review-does-not-gate.md` one level up.

**Review the stack after every wave** was rejected as the same review repeated at increasing cost, with its most valuable axis — the parent spec's coverage — answerable only once the last layer is in.

## Consequences

A run costs one more review than it did, once, at the end. The diff is named by ref pair rather than by checkout: `/code-review` fans out to sub-agents that run `git diff` in the orchestrating session's working tree, which is on none of the layer branches, so a worktree cut for the review would not be the tree they read. Reviewing at the trunk works only because every layer is rebased onto the layer below and the bottom onto the trunk, so `trunk...top` is exactly the run's product; a chain-mode run has the same property, since chain mode drops only the stack object.

The review is skipped where it can say nothing new — nothing stacked, or one layer stacked, which is the diff the per-layer review already read. The report says which, and says so on the same line that would otherwise carry findings: a run that never looked across its layers cannot be read as a run that looked and found nothing.

A named set with no parent has no stack-level spec. The Standards axis still runs; the run tells `/code-review` there is no spec, so the Spec axis skips instead of stopping to ask for one.
