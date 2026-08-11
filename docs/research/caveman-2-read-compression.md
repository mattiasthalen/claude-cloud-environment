# Caveman 2.0 "read compression" and whether it would help this repo

Question: would the read-compression capability shipped in Caveman 2.0
([`JuliusBrussee/caveman`](https://github.com/JuliusBrussee/caveman)) be
beneficial in `mattiasthalen/claude-cloud-environment`?

Short answer: **no, not as things stand.** Read compression is not part of the
Claude Code plugin this repo installs, it cannot be reached without adding a
second install channel (npm package plus signed Go binaries plus a local daemon)
into `environment.sh`, and the workload it is measured on — large tool payloads
of logs, JSON and CSV — is not the workload of a 908 KB shell-script repo. The
conditions under which the answer would flip are listed at the end.

## Method

Primary sources only. Claims about Caveman are taken from the project's own
source at the `v2.0.0` tag and from `origin/main`, read out of the local clone at
`/root/.claude/plugins/marketplaces/caveman` (remote
`https://github.com/JuliusBrussee/caveman.git`), cross-checked against the
project's own Markdown (`ANNOUNCEMENT.md`, `README.md`, `docs/WRAP-BENCHMARK.md`,
`docs/HONEST-NUMBERS.md`, `SECURITY.md`). Claims about Claude Code mechanisms are
taken from [code.claude.com/docs](https://code.claude.com/docs). Claims about
this repository are taken from its own files. No blog posts or third-party
write-ups were used.

Where the project asserts a number, the text below says so and names the claim
label the project itself attaches to it. Statements marked *verified* were
checked directly against source in the clone.

## What "caveman 2.0" read compression is

### The framing the project uses

The project's own announcement states the split plainly: "Caveman v1 shrank the
model's **mouth**. […] Caveman 2 adds the **ears**. It shrinks what the model
*reads*."
([`ANNOUNCEMENT.md`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/ANNOUNCEMENT.md))
v2.0.0 was tagged 2026-08-11 and is the current GitHub latest release
([releases](https://github.com/JuliusBrussee/caveman/releases)); the single
commit that introduces it is
[`82864c8`](https://github.com/JuliusBrussee/caveman/commit/82864c8), "feat: ship
Caveman 2.0.0 — engine, proxy, SDKs, unified CLI".

### The components (verified)

Read compression is not one thing. Three distinct mechanisms ship under the
banner, and only the last two touch Claude Code:

1. **The engine** — a Go library at
   [`engine/`](https://github.com/JuliusBrussee/caveman/tree/v2.0.0/engine) with
   per-content-type compressors (`json.go`, `log.go`, `code_cgo.go`, `diff.go`,
   `searchresult.go`, `tabular.go`, `terminal.go`, `html.go`, `toolschema.go`,
   TOON encoders). `detect()` types a payload and routes it.
2. **The proxy** — a local HTTP proxy the agent's provider base URL points at
   ([`proxy/`](https://github.com/JuliusBrussee/caveman/tree/v2.0.0/proxy)),
   launched by `caveman claude`. This is the path the headline benchmark
   measures.
3. **The native hook** — a Claude Code hook binary that mutates tool results in
   place, at
   [`packages/cli/src/native-hook-fast.ts`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/packages/cli/src/native-hook-fast.ts).

### What the native hook actually hooks into (verified)

The hook registers on the full Claude Code lifecycle, not just reads. The
installer writes one hook entry per event into the agent's settings for
`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PostToolUseFailure`, `PreCompact`, `PostCompact`, `SubagentStart`,
`SubagentStop`, `Stop`, `SessionEnd` (`nativeHooksDocument()` in
[`packages/cli/src/index.ts`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/packages/cli/src/index.ts)),
plus an optional `shrink-hook` on `PreToolUse` and an optional `mem recall-hook`
on `UserPromptSubmit`.

The compression itself is delivered on `PostToolUse`. The hook emits:

```json
{"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedToolOutput": "…"}}
```

only when the agent is `claude`, the policy mode is not `record`, and the runtime
returned an `output_replacement` (`main()` in `native-hook-fast.ts`).

`updatedToolOutput` is a real, documented Claude Code facility, not a hack: the
hooks reference states that for `PostToolUse`, "`updatedToolOutput` replaces the
tool's result" ([hooks reference](https://code.claude.com/docs/en/hooks)). The
docs also endorse the general pattern — "Custom hooks can preprocess data before
Claude sees it. Instead of Claude reading a 10,000-line log file to find errors,
a hook can grep for `ERROR` and return only matching lines"
([manage costs](https://code.claude.com/docs/en/costs)).

The hook does not do the work itself. It serialises the event and sends it over a
Unix socket at `~/.caveman/run/native.sock` (a named pipe on Windows) to a
long-running local runtime, with a 250 ms timeout, and falls open — writing a
JSONL record and emitting nothing — if the socket is absent
(`callRuntime()`/`fallback()` in `native-hook-fast.ts`). So the hook alone is
inert; the daemon is required.

### What gets compressed, and what is preserved

*Verified from source.* The runtime classifies each tool by name
(`classifyTool()` in
[`proxy/internal/nativeruntime/runtime.go`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/proxy/internal/nativeruntime/runtime.go)):
a name containing `read` or `view_file` becomes a `FileObservation`; `search`,
`grep`, `rg` or `find` becomes a `SearchResult`; `write`/`edit`/`apply_patch`
becomes a `DiffSnapshot`; commands matching `test`/`build` get their own types.
So yes — Read, Grep and Glob results are in scope.

Two different things can then happen to that payload:

- **Elision** (the engine). Per-type behaviour is tabulated by the project in
  [`README.md`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/README.md):
  `json` keeps keys, structure and error subtrees, target 70–90%; `log` keeps
  errors, stack traces, first/last lines, 85–95%; `code` keeps imports,
  signatures and types while eliding function bodies, 40–70%; `diff` keeps file
  and hunk headers, 60–80%; `search-result` keeps top/bottom hits plus
  diagnostic/security hits, 80–95%; text/HTML keeps headings and important
  sections, 50–80%. The README labels **all** of these targets `inferred`, i.e.
  local tokenizer estimates, not measured savings.
- **Masking**. When the payload is large enough and cannot be usefully
  summarised, the whole tool output is replaced with a four-line stub naming a
  `ccr://` recovery handle and instructing the agent to call `caveman_retrieve`
  to get the bytes back (`runtime.go`). Masking only fires when the original
  exceeds the stub plus a 384-byte margin.

The code compressor is the one that matters for file reads, and it is worth
being precise about it. It is explicitly written for Claude Code's Read output:
the source comment for `SplitLineNumberedListing` says agents "hand it a FILE
LISTING: the file's text with every line prefixed by its line number, the shape
`cat -n` and every Read tool emit (Claude Code writes `%d\t` …)"
([`engine/compressors/code_listing.go`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/engine/compressors/code_listing.go)).
It strips the gutter, compresses the source, and puts the gutter back.

The compression is a tree-sitter parse that replaces every function body with
`{ /* caveman: body elided */ }` (or `...` in Python), keeping imports,
signatures and type/class declarations
([`engine/compressors/code_cgo.go`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/engine/compressors/code_cgo.go)).
Comments and docstrings are kept by default
([`code_options.go`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/engine/compressors/code_options.go)).
Languages supported under cgo: Go, Python, JS/TS, Rust, Java, C, C++; the pure-Go
fallback handles Go only (README). **Shell is not among them**, so a `.sh` file
falls through to the generic text path or passes through untouched.

### Is it lossy?

Yes, and the project says so in its own source: the code compressor "is S4
(lossy); the original is recoverable via CCR" (`code_cgo.go`). Recovery is a
content-addressed local store
([`engine/ccr/`](https://github.com/JuliusBrussee/caveman/tree/v2.0.0/engine/ccr)),
and the README's safety gates say original bytes land in CCR *before* a lossy
transform goes upstream, with pass-through on any parse problem, store failure or
larger result.

### The savings numbers, and where they come from

Two numbers circulate, and they are not the same claim.

- **93%** — "a 40-record JSON blob going from 16,098 tokens to 1,091". The
  announcement itself labels this **inferred**: "this is what you *could* save,
  measured on your own machine" (`ANNOUNCEMENT.md`). It is a single JSON fixture,
  not a session measurement, and it is not a file read.
- **33.2% fewer provider-reported input tokens** — the headline README claim,
  documented in
  [`docs/WRAP-BENCHMARK.md`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/docs/WRAP-BENCHMARK.md).
  This is the substantive one and it is unusually well specified: 591,673 vs
  885,793 provider-counted input tokens across 18 paired runs, 18/18 exact-answer
  checks passed, case-clustered 95% interval 14.6%–48.5%, Claude Code `2.1.223`,
  model `claude-sonnet-5`, using Claude Code's own `modelUsage` counters
  (`input_tokens + cache_read_input_tokens + cache_creation_input_tokens`).

Three caveats about that 33.2%, all stated by the project itself in the same
file. It is labelled `benchmark_counterfactual` — "controlled benchmark evidence,
not production traffic, customer spend, a provider invoice, or Caveman
`verified_savings`". The six fixtures are 60–95 KB MCP payloads of logs, JSON,
CSV, test output, YAML and HTML — **none of them is a source-file read**. And one
of the six regressed: `dashboard-html-alert` came out **-9.9%**, because no
transform applied while skill overhead was still counted. The harness itself
lives in a different repository
([`JuliusBrussee/Caveman-Cloud`](https://github.com/JuliusBrussee/Caveman-Cloud/tree/630e157246b68b63559fb8baab29b87042db996b/internal/wrapbench)),
so the benchmark is not independently reproducible from this repo alone.

## How it differs from the caveman we already have installed

*Verified against the local install.*

| | Installed today | Caveman 2.0 read compression |
| --- | --- | --- |
| Delivery | Claude Code plugin `caveman@caveman` | separate npm CLI + signed Go binaries + local daemon |
| Hook surface | `SessionStart`, `UserPromptSubmit` | 11 lifecycle events, incl. `PostToolUse` |
| What it shrinks | model **output** (prompt instruction) | model **input** (tool results) |
| Lossy? | style only, no payload rewritten | yes, S4, CCR-recoverable |
| Own measured claim | none published for output reduction | 33.2% input, `benchmark_counterfactual` |

The plugin cache is at
`/root/.claude/plugins/cache/caveman/caveman/309834233183…`, i.e. upstream commit
`3098342` ("Update README.md with Skills.sh badge", 2026-08-10) — the last commit
on `main` before the 2.0 import. Upstream latest is `v2.0.0` (2026-08-11), so the
install is **one release behind**, and pre-2.0.

That gap matters less than it looks, because of the decisive finding: **the
Claude Code plugin manifest is byte-identical before and after 2.0.**
`.claude-plugin/plugin.json` at `origin/main` still declares exactly two hooks,
`SessionStart` → `caveman-activate.js` and `UserPromptSubmit` →
`caveman-mode-tracker.js`. Nothing in the plugin references the engine, the
proxy, the native hook or `PostToolUse`. The announcement is consistent with
this: "The skill you starred is untouched. […] nothing has changed for you."

So re-running `claude plugin install caveman@caveman` after 2.0 does **not** get
read compression. It arrives only via `npm i -g @caveman-ai/cli` followed by
`caveman setup --install`, which downloads signed runtime binaries, and then
`caveman claude`
([`engine/README.md`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/engine/README.md),
README install section). The npm package is published — `@caveman-ai/cli` is at
`1.0.0` on the registry, verified via `registry.npmjs.org`.

The installed plugin does ship a *different* compression feature,
`/caveman-compress`, which rewrites memory files such as CLAUDE.md into caveman
prose. That is a one-off file rewrite, unrelated to tool-result compression, and
this repo already denies it (see below).

## Risks

**Information loss on code reads.** Body elision is exactly the wrong shape of
loss for a repo whose content *is* function bodies. For an agent asked "what does
this function do", a signature-only view is a dead end that costs a recovery
round-trip. The project's own defence is the CCR recovery path, and its own
source records that path going badly: masked payloads in its `2026-08-08`
measurement scored **0/6 with 27–97 recovery calls**, and the comment concludes
that masking a structured payload is "strictly worse than no wrap at all"
(`maskWouldDiscardFacts` in `runtime.go`). That regression is why the
`maskWouldDiscardFacts` gate exists; the fact that it had to be added is the
warning.

**Interaction with Claude Code's own context management.** Claude Code already
does two of the things read compression is sold as doing: prompt caching, which
re-reads history at the cached rate, and auto-compaction, which summarises older
history near the context limit ([manage
costs](https://code.claude.com/docs/en/costs),
[context window](https://code.claude.com/docs/en/context-window)). Caveman
registers on `PreCompact` and `PostCompact` and offers "cache-aware" and
"ccr-masking" profiles (`resolveProfile()` in `runtime.go`), which is an
acknowledgement that the interaction is delicate rather than a proof it is
benign. Anything that rewrites request bodies turn over turn risks moving cache
breakpoints, and a cache miss reprocesses the full context. The project's own
`docs/HONEST-NUMBERS.md` reports exactly this failure mode for v1 in another
agent — a Cursor A/B at "4.3M tokens with caveman vs 1M without" — and its
conclusion is "if your A/B looks like that, caveman is net-negative for you. Turn
it off."

**It does need a hook that mutates tool output.** That is the mechanism, not an
implementation detail. It is documented and supported, but it means every Read,
Grep, Glob and Bash result in the session passes through third-party code before
Claude sees it, and the agent has no way to tell that what it read is not what is
on disk beyond the stub text.

**Permission and security surface.** Installing it means: a globally installed
npm package; downloaded prebuilt Go binaries (the CLI verifies a signed checksum
manifest and each binary's SHA-256 before an atomic install, per the README); a
long-running local daemon holding a Unix socket; hook entries on 11 lifecycle
events written into `settings.json`; a local CCR store on disk holding the
original bytes of everything the agent read; and, on the proxy path, all provider
traffic routed through `127.0.0.1`. The project's own
[`SECURITY.md`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/SECURITY.md)
is candid: in local mode nothing goes to Caveman, CLI telemetry is opt-in and off
by default, but "Managed Caveman gateway" mode does transit Caveman Cloud, and
"Do not treat managed mode as local-only." Licensing is also split — the engine,
proxy and MCP server are BSL-1.1, not MIT
([`LICENSING.md`](https://github.com/JuliusBrussee/caveman/blob/v2.0.0/LICENSING.md));
self-hosting for your own traffic is free, reselling is not, and BSL sunsets to
Apache-2.0 in roughly four years.

## Fit for this repository

What this repo is, from its own files: `environment.sh` is the setup script for
Claude Code on the web environments, fetched at an immutable tag and piped into
`bash` (`README.md`). Measured: 58 tracked files, 908 KB working tree, 42 `.sh`
and 10 `.md` files, ~3,800 lines across shell and Markdown, with `environment.sh`
itself at 37 KB the single largest file. There is no application source, no
JSON/CSV/log corpus, and no compiled language.

Against that, the numbers do not work:

- **The compressor that would fire has nothing to bite on.** Shell is not a
  supported tree-sitter language in the code compressor, and the whole repo is
  smaller than a single one of the benchmark's six fixtures — every fixture was
  60–95 KB; the entire tracked tree is ~900 KB including `.git`. A session here
  reads a handful of small shell and Markdown files.
- **The session shape is wrong.** Time here goes into container test runs and
  `gh` calls, not into re-reading a large corpus. Where output *is* verbose —
  `./tests/run.sh` — the repo's own `docs/agents/testing.md` gate already exists,
  and Claude Code's documented answer is a `PreToolUse` filter hook you write
  yourself in a few lines ([manage
  costs](https://code.claude.com/docs/en/costs)), with none of the daemon.
- **It cannot arrive through the channel this repo uses.** `environment.sh`
  installs caveman with `claude plugin marketplace add JuliusBrussee/caveman` and
  `claude plugin install caveman@caveman`. Read compression is not in that
  plugin. Adding it means a second install channel — npm global install plus
  binary download plus a daemon — into a script whose contract is "pinned
  versions, fail the run if anything did not land". The binaries are downloaded
  at whatever version `caveman setup --install` resolves, which is a moving
  target unless separately pinned.
- **It fights the repo's existing stance on caveman.** `environment.sh` writes
  `permissions.deny` entries for `Skill(caveman:cavecrew)`,
  `caveman-review`, `caveman-commit`, `caveman-compress`, `caveman-help`,
  `caveman-init` and `caveman-stats`, leaving only the `caveman` level switcher
  reachable. The comment says the plugin "is enabled for its response style alone"
  and that the repo "wants the response style and nothing else from the plugin".
  Read compression is emphatically something else from the plugin's vendor, and
  the deny list is checked at *skill invocation* — it would not constrain a hook
  or a daemon at all.
- **The environment may not support it.** These are Claude Code on the web
  containers. `AGENTS.md` already records that a hosted web session cannot run
  the container test suite (no daemon, no Docker Hub). A long-lived Unix-socket
  daemon plus downloaded binaries in an ephemeral web container is at best
  unproven here, and `environment.sh` would have to verify it landed, per its own
  contract.
- **The one honest measurement points the other way for small sessions.** The v1
  skill already costs ~1–1.5k input tokens per turn by the project's own
  accounting (`docs/HONEST-NUMBERS.md`), and its stated rule of thumb is: if
  fixed overhead exceeds the reduction, turn caveman off for that workload. Read
  compression adds its own fixed overhead — an MCP toolkit exposing
  `caveman_retrieve`, plus per-turn hook latency — on a repo with very little
  input to reduce.

## Recommendation

**Not beneficial. Do not adopt.** Keep the plugin where it is — the response
style, the deny list, the pinned-tag install — and do not add the CLI, the
binaries, the daemon or the native hooks to `environment.sh`.

Conditions that would change the answer, any one of which is a genuine trigger to
re-run this analysis:

1. **Upstream folds read compression into the plugin.** If
   `.claude-plugin/plugin.json` ever gains a `PostToolUse` hook that works
   without out-of-band binaries, the cost of trying it drops to near zero and it
   becomes a cheap experiment.
2. **The provisioned environments' real workload changes shape.** The tools this
   script installs — `gcloud`, `kubectl`, `snow`, `prefect`, `newrelic` — emit
   exactly the JSON/log/tabular payloads the benchmark measures. If sessions in
   the *provisioned* environments (as opposed to sessions in this repo) start
   burning context on large CLI output, the calculus flips — but the beneficiary
   would be those environments, not this repository, and the honest first move is
   still a `PreToolUse` filter hook rather than a compression daemon.
3. **A measurement exists that this repo trusts.** The project's own rule is that
   an A/B against provider-billed totals outranks anything it prints. Nobody
   should adopt this on the 33.2% figure alone; it was measured on payload shapes
   this repo does not have, and one of its six cases regressed.
4. **The daemon is shown to survive a hosted web container**, and a pinnable
   version of the binaries exists that `environment.sh` can verify the way it
   verifies every other pin.
