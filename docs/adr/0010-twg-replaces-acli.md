# twg replaces acli

Atlassian ships the Teamwork Graph CLI (`twg`) as its agent-first interface to
Jira, Confluence and the rest of the graph — exactly the consumer a provisioned
session is. `twg` joined the selectable-tool set first (#81); this decision is
about what happens to `acli` once it did, and the answer is that `acli` leaves
the valid set entirely rather than sitting alongside `twg`. A box that still
names `acli` on its setup line fails argument validation loudly, naming the
unknown tool and the valid set, with nothing installed — there is no tombstone
arm translating the old name to the new tool and no alias accepting both.

This holds even though Atlassian has not deprecated `acli` and describes `twg`
and the Rovo MCP server as complementary to it, not as a replacement for it.
That framing is about what Atlassian offers across every kind of consumer —
humans doing ad hoc administration, CI jobs, MCP-driven agents — not about what
one script provisioning one class of box should carry. Exactly one environment
requested `acli`, its owner is migrating it to `twg`, and two Atlassian CLIs
serving one box is inventory this repo carries, not capability a session gains.
Recording that explicitly is the point of this file: without it, "Atlassian
calls them complementary" reads as new information the next time someone
reaches for the valid-tools list, and a well-meaning restoration of `acli`
undoes the swap this ADR chose on purpose.

The swap also removes the script's only unpinned tool. `acli`'s apt repository
carries a single `stable` suite with exactly one version, so nothing about it
could be pinned — verification for `acli` could only assert liveness, never a
version, which is the one carve-out `verify_runs` existed to cover. `twg`
publishes per-version binaries with checksums on its own download host, so it
installs through the release path — the same shape as `kubelogin`, `newrelic`
and `helm` — pinned and verified against the lockfile like every other tool.
`verify_runs` goes back to having only add-ons as its clientele.

## Considered options

- **Add `twg` alongside `acli`, keep both selectable** — rejected. Reversibility
  was its only virtue: restoring a deleted case arm is cheap if this turns out
  wrong. Set against that, every future reader of the valid-tools list would
  have to work out which of the two Atlassian CLIs an environment should ask
  for, on every environment, forever — and the one tool this script could never
  pin would keep sitting in the lockfile as a standing exception.
- **Wait for an Atlassian deprecation notice before removing `acli`** —
  rejected. None is coming on any known schedule; Atlassian's own materials
  describe the two CLIs as serving different audiences indefinitely, not as a
  transition. The one affected environment wants the agent-first CLI now, and
  a script that provisions agent sessions has no use for the human-administration
  tool once the agent-first one covers the same graph.
- **Alias `acli` to install `twg`** — rejected. A box author who typed `acli`
  meant the acli binary and its flags; silently handing them a different CLI
  under the old name is a worse surprise than a loud validation failure naming
  the valid set, and it is exactly the kind of "helpful" translation that makes
  a removed name look like it never left.

## Consequences

- Removing a tool name changes the invocation contract, so this ships as a
  MAJOR bump (`SCRIPT_VERSION` 2.0.0): a box whose setup line still says `acli`
  fails argument validation at the tag that carries this change and must be
  rewritten, which is the deliberate signal rather than a silent no-op or a
  quiet install of something nobody chose.
- The Atlassian apt repository setup (`setup_repo_atlassian`, the `atlassian`
  vendor arm) is deleted with the tool. No dead vendor plumbing — keyring,
  sources list, package name — survives the swap for a repository nothing
  installs from anymore.
- Authentication moves from `acli`'s environment variables to the ones `twg`
  reads (`TWG_TOKEN`/`TWG_USER`, `TWG_OAUTH_ACCESS_TOKEN`, `TWG_BBC_TOKEN`),
  documented in the README. Credentials stay the box's business; the script
  configures none of them, for either tool.
- The four `acli` test cases retire with the tool, and the cases whose
  assertions depended on the old valid-tools vocabulary — the unknown-tool
  message, the all-valid-names parse — are updated to the new one rather than
  left asserting on a name that no longer validates.
