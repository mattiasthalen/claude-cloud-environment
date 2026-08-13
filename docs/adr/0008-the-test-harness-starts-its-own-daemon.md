# The test harness starts its own daemon

`tests/run.sh` starts `dockerd` itself when no daemon answers, it finds `dockerd` on PATH, and it is root or has passwordless sudo. This reverses issue #48, which closed with "Deliberately no code change", an acceptance criterion of "No change to `tests/run.sh`, `tests/lib.sh` or any case", and "Any daemon-start automation" listed under Out of scope. Anyone arriving at this repo from that issue is reading a decision that no longer holds, and this ADR is the only thing that will tell them so.

#48 was not wrong when written. It rested on #43's finding that a hosted web session cannot reach Docker Hub — a `403 Forbidden` on `ubuntu:24.04` metadata, with the proxy answering `403` to `CONNECT` for `production.cloudfront.docker.com` — and on that premise, starting the daemon buys a second wall instead of a green suite. Automating a dead end is worse than documenting it, which is what #48 decided and why it forbade the code change rather than merely declining to prioritise it.

The premise no longer reproduces. Docker Hub answers, and the failure that appears instead is `429 Too Many Requests` on the anonymous pull limit, which clears by itself after tens of minutes rather than standing as a policy wall. With the daemon started and one rate-limit wait, the full `quick` tier passed 18 of 18 inside a hosted web session. The wall #48 was built around is gone, so its conclusion goes with it.

Two facts about the environment make the automation worth having rather than merely possible. PID 1 in a hosted session is the session's own supervisor rather than an init system, so nothing ever starts the installed daemon. And a daemon started by hand does not survive the command that started it — it is reaped even under `setsid` with output redirected and stdin closed — so "start it once at the top of your session" is not a workaround that holds. Starting it inside `tests/run.sh`, per run, is the only placement that survives.

## Considered options

**Leaving #48 as it stands and running the suite only in CI** was the status quo, and remains what the pull-request gate does. Rejected as the sole answer because it costs a full CI round trip to learn what a local run now answers in a minute, and because the discovery path #48 complained about is still there in reverse: a session that believes the docs will not try, and will not find out that the wall has gone.

**Reporting a better error instead of starting the daemon** — #48's own "original proposal" — was rejected for the reason #48 gave, which survives the change of premise: a nicer message about a thing the caller cannot fix is worth less than doing it for them, now that doing it works.

**Starting the daemon unconditionally, or from `tests/lib.sh` so cases could start it too**, was rejected. The three guards keep the attempt to the one environment that needs it; anywhere else — Docker Desktop, a rootless daemon, a CI runner with a socket mounted in — the original `exit 2` stands untouched. Cases get their daemon from the run that invoked them and have no business starting one.

## Consequences

Issue #48's acceptance criteria are now contradicted by the tree, and closed issues are not edited. This ADR is the record; `docs/agents/testing.md` carries the operational half.

The rate limit is not solved, only survived. A local run can still be unavailable for reasons that have nothing to do with the change under test, which is why the `quick` tier on the pull request remains the gate and a local pass is a faster signal rather than a replacement.
