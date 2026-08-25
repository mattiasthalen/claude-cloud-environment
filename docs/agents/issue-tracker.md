# Issue tracker: GitHub

Issues and specs live as GitHub issues, in whichever repository the session is
working in. Infer that repository from the git remote — `git remote -v` in the
checkout; the `gh` CLI does it automatically when run inside one — and never
hardcode one here.

## Which surface to use, in order

Every operation below is described as a `gh` command, because that is the
shortest way to write it. The command is the *operation*, not the transport. Use
the first of these that is available:

1. **The `gh` CLI**, when it is on the PATH and authenticated.
2. **The GitHub MCP server tools**, where they cover the operation — reading and
   writing issues, comments, labels, sub-issues, pull requests, reviews.
3. **Authenticated REST or GraphQL** against `https://api.github.com`, where
   they do not.

Some environments (for example Claude Code on the web) have no `gh` on the PATH
at all, so surfaces 2 and 3 are the whole toolkit there. The conventions below
still describe *what* to do; only the transport changes.

### Operations no MCP tool covers

These are reachable, and a session that finds no MCP tool for them should reach
for REST or GraphQL rather than concluding they are impossible:

- **Issue dependencies** — adding and reading blocking edges. REST only; the
  endpoints are written out in the Blocking bullet under Wayfinding operations
  below.
- **The draft and ready mutations** — marking a draft pull request ready for
  review (`markPullRequestReadyForReview`) and converting one back to a draft
  (`convertPullRequestToDraft`). GraphQL only, at
  `https://api.github.com/graphql` with the same token; both take the pull
  request's `node_id`.
- **Stack objects** — creating a stack of pull requests and adding a layer to
  it. REST only; `/swarm` carries the calls it makes, and stacked pull requests
  are in public preview, so a repository where the stack API does not answer is
  a normal outcome rather than a fault.

Endpoints are written out here only where they are already known to work. Where
this doc names an operation without an endpoint, look the endpoint up rather
than inventing one that reads plausibly.

### When there is no credential for an operation

An operation the session holds no usable credential for is **parked**, with the
reason stated — the operation, the surface it needs, and what is missing. Do not
route around it with a substitute that records something different: a `Blocked
by:` line written into a body is a documented fallback for a tracker without
dependencies, not a stand-in for a dependency edge the session merely could not
authenticate for.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either — resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies** — the canonical, UI-visible representation. Add an edge by POSTing to `repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by` with `issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (the `id` field of `repos/<owner>/<repo>/issues/<n>`, _not_ the `#number` or `node_id`). With the `gh` CLI that is `gh api --method POST ... -F issue_id=<blocker-db-id>`; without it, call the same REST endpoints directly. GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only — the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Ready for work**: the label `ready-for-agent`. A ticket carrying it is fully specified and safe to hand to an agent. `/swarm` reads this name from here when a bare invocation offers to build a map out of the ready tickets: `gh issue list --state open --label <that label> --search "no:assignee"`. It is the same string as the ready-for-work triage role in `triage-labels.md`; that table stays the place to rename it, and this bullet names it once so a rename is two edits rather than three.
- **Claim**: `gh issue edit <n> --add-assignee @me` — the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
