# Code review does not gate integration in a swarm run

A swarm run reviews each ticket branch before it is merged into the integration branch, so it would be easy to assume an unclean review holds the merge back. It does not: a ticket whose review returned open findings, or whose review could not run at all, still integrates, and the debt is carried on the ticket and in the run's report. Only a red check suite blocks a merge.

## Considered options

The alternative is to gate — hold `issue/NN` out of `task/<slug>` until its findings are fixed. It was rejected because a swarm run's frontier is a dependency graph: a held ticket blocks every ticket that depends on it, so one contested finding can stall a whole wave while the orchestrator waits on a judgement call the user has not made yet. Review findings are also advisory by nature — a finding can be wrong, or can contradict the ticket's acceptance criteria — while a red suite is not. Gating on the advisory signal and the objective one alike gives the weaker signal the stronger power.

## Consequences

Unreviewed and unfixed work can reach the integration branch, so the run's report is the only thing standing between that and silence. This is why the *Landed with open review items* block is mandatory, why an absent block has to mean "nothing is open" rather than "nobody looked", and why the block is repeated verbatim into any pull request body the run writes. Weakening the report weakens the decision this ADR records.
