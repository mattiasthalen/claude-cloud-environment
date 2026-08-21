# twg replaces acli

Atlassian ships the Teamwork Graph CLI (`twg`) as its agent-first interface to
Jira, Confluence and the rest of the graph — exactly the consumer a provisioned
session is. We replace `acli` with `twg` in the selectable-tool set rather than
carrying both, even though Atlassian has not deprecated acli and describes the
two (and the Rovo MCP server) as complementary: exactly one environment
requested acli, its owner is migrating it, and two Atlassian CLIs serving one
box is inventory, not capability.

The swap also removes the script's only unpinned tool. acli's apt repository
carries a single `stable` version, so it could not be pinned; twg publishes
per-version binaries with checksums on the vendor host, so it installs through
the release path, pinned and verified like every other tool.

## Considered options

- **Add twg alongside acli** — rejected. Reversibility was its only virtue, and
  restoring a deleted case arm is cheap; meanwhile every future reader of the
  valid-tool list would wonder which of the two Atlassian CLIs an environment
  should ask for.
- **Wait for an Atlassian deprecation notice** — rejected. None is coming on
  any known schedule, and the one affected environment wants the agent-first
  CLI now.

## Consequences

- Removing a tool name changes the invocation contract, so this ships as a
  MAJOR bump: a box whose setup line still says `acli` fails argument
  validation at the tag that carries this change and must be rewritten, which
  is the deliberate signal rather than a silent no-op.
- Authentication moves from acli's environment variables to the ones twg reads
  (`TWG_TOKEN`/`TWG_USER`, `TWG_OAUTH_ACCESS_TOKEN`, `TWG_BBC_TOKEN`).
  Credentials stay the box's business; the script still configures none of
  them.
