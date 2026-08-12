# Code review does not gate a swarm ticket's progress

A swarm run reviews each ticket branch before that ticket's work is published, so it would be easy to assume an unclean review holds it back. It does not: a ticket whose review returned open findings, or whose review could not run at all, still ships, and the debt is carried on the ticket and in the run's report. Only a red check suite blocks it.

*Amended when `0002-a-swarm-run-ships-a-stack-of-pull-requests.md` retired the integration branch.* The decision is unchanged; what it gates has moved. It used to mean "the ticket still merges into `task/<slug>`". It now means "the layer is still rebased onto the layer below, stacked, and marked ready".

## Considered options

The alternative is to gate — hold the ticket back until its findings are fixed. It was rejected because a swarm run's frontier is a dependency graph: a held ticket blocks every ticket that depends on it, so one contested finding can stall a whole wave while the orchestrator waits on a judgement call the user has not made yet. Review findings are also advisory by nature — a finding can be wrong, or can contradict the ticket's acceptance criteria — while a red suite is not. Gating on the advisory signal and the objective one alike gives the weaker signal the stronger power.

Gating the draft-to-ready flip specifically was rejected for one further reason: a fix agent may legitimately refuse a finding that contradicts the ticket's acceptance criteria, and a gate would then leave that layer a draft with nobody left to unstick it. Ready means *swarm is finished with this layer*, not *review approved it*.

## Consequences

Unreviewed and unfixed work can reach a pull request marked ready, so the run's report is the only thing standing between that and silence. This is why the *Ready with open review items* block is mandatory, why an absent block has to mean "nothing is open" rather than "nobody looked", and why the report is written where it outlives the session. Weakening the report weakens the decision this ADR records.

The human reviewing each layer before merging is now a real second gate, which is part of why one fix pass is enough — but it is theirs, not swarm's, and swarm never waits on it.
