# Remote Control is not what powers `add_repo` / `list_repos`

Question: in Claude Code on the web, is the **Remote Control** toggle the thing that enables the `add_repo` / `list_repos` tools — the MCP server that lets a cloud session attach a GitHub repository mid-session? Should it be turned on to widen repository scope?

Short answer: no. Remote Control and the cloud-session repository tools are unrelated features that share the word "remote" and nothing else. This environment ships with Remote Control disabled and `list_repos` still works, measured directly.

## Method

Every claim below is either taken from Anthropic's own documentation and the `anthropics/claude-code` CHANGELOG, or measured inside this cloud session. Claims that could not be traced to a primary source are marked **UNVERIFIED** and are not asserted as fact.

## Summary

| | Remote Control | `add_repo` / `list_repos` |
| --- | --- | --- |
| What it is | A transport that lets claude.ai/code and the Claude mobile app drive a Claude Code session running **on your own machine** | MCP tools exposed inside an Anthropic-hosted **cloud** session for attaching and listing GitHub repositories |
| Where code executes | Your machine | The cloud VM |
| Controlled by | `disableRemoteControl` setting, the org-level Remote Control admin toggle, `remoteControlAtStartup` | Not controlled by any documented setting; governed by the connected GitHub account's own access |
| Relevant to a cloud session's repo scope | No | Yes |

## What Remote Control actually is

Remote Control connects the web and mobile clients to a Claude Code process running locally. It is the opposite direction of travel from a cloud session:

> Remote Control connects [claude.ai/code](https://claude.ai/code) or the Claude app for iOS and Android to a Claude Code session running on your machine. Start a task at your desk, then pick it up from your phone on the couch or a browser on another computer.

> Unlike [Claude Code on the web](/docs/en/claude-code-on-the-web), which runs on cloud infrastructure, Remote Control sessions run directly on your machine and interact with your local filesystem. The web and mobile interfaces are a window into that local session.

Source: <https://code.claude.com/docs/en/remote-control>

The docs go out of their way to separate the two concepts:

> `--cloud` creates cloud sessions. `--remote-control` is unrelated: it exposes a local CLI session for monitoring from the web. See [Remote Control](/docs/en/remote-control).

Source: <https://code.claude.com/docs/en/claude-code-on-the-web>

It is activated deliberately, per-session, from the local machine — `claude remote-control` (server mode), `claude --remote-control` / `--rc`, or `/remote-control` in an existing session — with an optional auto-connect setting (`remoteControlAtStartup`, or **Enable Remote Control for all sessions** in `/config`). All of these run on your machine. None of them exist inside a cloud session. Source: <https://code.claude.com/docs/en/remote-control>

The one place a cloud session touches Remote Control at all is plumbing reuse for `--teleport`, and even there the docs describe it as shared infrastructure, not shared functionality:

> `--teleport` connects through the same Remote Control session infrastructure that cloud sessions use, so authentication and session-expiry errors surface with Remote Control wording.

Source: <https://code.claude.com/docs/en/claude-code-on-the-web> (Troubleshooting → "Remote Control session expired or access denied")

The settings reference confirms the scope of the kill switch:

> `disableRemoteControl` — Disable Remote Control: blocks `claude remote-control`, the `--remote-control` flag, auto-start, and the in-session toggle. Typically placed in managed settings for per-device MDM enforcement, but works from any scope.

Source: <https://code.claude.com/docs/en/settings> (Available settings)

Note that this enumerates exactly four things it blocks — a CLI subcommand, a CLI flag, auto-start, and the in-session toggle. Repository access is not among them, and no repository behaviour is mentioned anywhere on the Remote Control page.

## What actually governs repository scope in a cloud session

Repository access in cloud sessions is a function of the connected GitHub identity, not of any Claude Code toggle:

> With either method, a cloud session can access any repository the connecting GitHub account can see, not just the repositories the Claude GitHub App is installed on. App installation enables PR webhooks for Auto-fix; it is not a session-level access control. To restrict which repositories your team can reach from cloud sessions, restrict access on GitHub itself, for example by limiting team or repository membership for the connected GitHub accounts.

Source: <https://code.claude.com/docs/en/claude-code-on-the-web> (GitHub authentication options)

And multi-repository sessions are a documented, first-class capability of the web product, described purely as a UI affordance with no mention of Remote Control:

> From claude.ai/code or the Code tab in the Claude mobile app, click the repository selector below the input box and choose a repository for Claude to work in. Each repository shows a branch selector. Change it to start Claude from a feature branch instead of the default. You can add multiple repositories to work across them in one session.

Source: <https://code.claude.com/docs/en/web-quickstart> (Start a task → Select a repository and branch)

The same page documents a `repositories` URL parameter for pre-selecting repos, again with no Remote Control dependency.

### On the `add_repo` / `list_repos` tools specifically

**UNVERIFIED**: the `mcp__Claude_Code_Remote__add_repo` and `list_repos` tools are not named anywhere in the Claude Code documentation or in the `anthropics/claude-code` CHANGELOG. Searching the CHANGELOG (5,399 lines, fetched from `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`) for `add_repo`, `list_repos`, `claude-code-remote`, and `claude_code_remote` returns zero matches, while `remote control` returns 60+ entries, all about the local-session feature. So there is no first-party description of these tools to cite; what follows is measurement, not documentation.

The tools are best understood as the programmatic equivalent of the documented "+ repo" UI affordance, and the naming collision is with the internal *Claude Code Remote* (CCR) cloud-session runtime — the same "CCR" that names this session's agent proxy directory `/root/.ccr/` and the `CCR_FORCE_BUNDLE` environment variable documented at <https://code.claude.com/docs/en/claude-code-on-the-web>. "Remote" there means "the cloud session", not "Remote Control".

## Measured evidence from this session

This cloud session runs with Remote Control explicitly and forcefully disabled:

- `/root/.claude/settings.json:50` — `"disableRemoteControl": true`
- `/home/user/claude-cloud-environment/environment.sh:674` — this repository's own environment bootstrap is what writes that key: `| .disableRemoteControl = true`
- `/root/.claude/settings.json:27-28` — the related outbound-messaging tools are denied too: `"SendMessage"`, `"PushNotification"`

Despite that, the repository tools are present and functional. Calling `list_repos` in this session returned:

```json
{"repos":[{"full_name":"mattiasthalen/claude-cloud-environment","url":"https://github.com/mattiasthalen/claude-cloud-environment","pushed_at":"2026-08-11T16:45:13Z","visibility":"public","can_push":true}],"has_more":false}
```

This is decisive for the question asked: `disableRemoteControl` is on, and `list_repos` works anyway. Turning Remote Control on would not change it.

## What turning Remote Control ON would enable

Only local-machine capability. From <https://code.claude.com/docs/en/remote-control>:

- Driving a Claude Code session running on your own machine from claude.ai/code or the iOS/Android app, with your local filesystem, MCP servers, tools, and project config staying available.
- Two-way sync across terminal, browser, and phone, including subagent and workflow progress.
- Sending images and files from the phone or browser into the local session.
- Mobile push notifications ("Push when Claude decides" / "Push when actions required"), which the docs state are only available "When Remote Control is active".
- Cross-session messaging: "the Remote Control connection also carries messages between your own Claude Code sessions on different machines, and messages arriving from your Claude Code on the web sessions." This is the `ListAgents` / `SendMessage` surface — CHANGELOG line 29 of the fetched file: "SendMessage can now start a conversation with your Remote Control sessions on other machines by name (`ListAgents` shows them as `name [ref]`)". Note this repo's environment already denies `SendMessage` separately.

None of these touch cloud repository scope.

### Security and privacy considerations

Worth weighing before enabling, all from <https://code.claude.com/docs/en/remote-control> (Connection and security):

- **Transcripts leave your machine and are stored server-side.** "While Remote Control is connected, the session transcript, including your messages, Claude's responses, and tool activity, is stored on Anthropic servers." Execution and filesystem access stay local, but the conversation does not.
- **No inbound ports.** "Your local Claude Code session makes outbound HTTPS requests only and never opens inbound ports on your machine." It registers with the Anthropic API and polls for work; credentials are multiple short-lived, single-purpose tokens.
- **Who can drive it: your account only, by default.** "Auto-connect signs in with your own claude.ai account, so a session it starts appears only in your own account's Claude apps and grants no one else access." The exposure is therefore anyone holding a valid session on your claude.ai account, from any browser or phone.
- **Trusted Devices (beta, Team/Enterprise) tightens that.** It requires an enrolled device plus a sign-in under 18 hours old, refreshable via Face ID / Touch ID / Windows Hello / passkey, before a member can view or steer a Remote Control session. Off by default; admin-enabled at claude.ai/admin-settings/claude-code.
- **Compliance blocks.** "Organizations with compliance requirements such as Zero Data Retention can't enable Remote Control."
- **Session sharing is a separate axis.** On Max/Pro, shared-session visibility is Private or Public, and "Repository access verification is not enabled by default" (<https://code.claude.com/docs/en/claude-code-on-the-web>). Worth checking independently of this toggle.

## About the toggle the user is looking at

**UNVERIFIED**: I could not verify the exact behaviour of the specific "Remote Control" control as rendered in the claude.ai/code settings UI, because that page is authenticated and not reachable as a primary source from here. The documentation describes three distinct Remote Control controls, and the one in question is most likely the second:

1. `disableRemoteControl` in a settings file — a hard kill switch, "typically placed in managed settings for per-device MDM enforcement, but works from any scope" (<https://code.claude.com/docs/en/settings>). This is what is set in this environment.
2. A per-account default: "**Desktop app**: Settings > Claude Code > Enable remote control by default", equivalent to `remoteControlAtStartup` and to "Enable Remote Control for all sessions" in `/config` (<https://code.claude.com/docs/en/remote-control>).
3. An organization-wide toggle at claude.ai/admin-settings/claude-code, Owner-only, off by default on Team and Enterprise: "This toggle is a server-side organization setting" (<https://code.claude.com/docs/en/remote-control>, Troubleshooting).

Whichever of these it is, all three gate the same local-session feature. None of them appear in any documentation about cloud sessions, repository selection, or repository access.

## Recommendation

Leave it off if the goal is repository scope — it will not help. `add_repo` and `list_repos` already work with it off, verified above, and what a cloud session can reach is set by the connected GitHub account's own permissions, changeable only on GitHub.

Turn it on only if the actual want is to steer a Claude Code session running on a personal machine from a phone or another browser, accepting that the transcript is then stored on Anthropic servers for the duration.

One caveat specific to this repository: `environment.sh:674` writes `disableRemoteControl: true` into every session's settings, so flipping any UI toggle will not survive here without editing that line.
