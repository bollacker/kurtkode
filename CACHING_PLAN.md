# Caching and the ChatGPT plan: implementation plan

2026-11-06. This is the plan that follows CACHING_REPORT.md. The goal is to make kurtkode's overall operation cost
less. Each item is either **ready**, meaning the facts it needs are known, or **gated**, meaning a probe or experiment
has to settle a question first. For each gated item the gate is given: what to measure, how, and what it costs.

R-numbers refer to the report's section 6.

## Principles for every item

- **Measure before and after.** Phase 0 comes first so that every later change shows up in `kurtkode cost report` as
  a change in cache share, miss causes and $/run, not as a claim.
- **History stays append-only between compactions.** Nothing here edits or trims earlier messages a little at a time.
- **Tests follow the repository's rules**:
  - unit tests on encoded request bodies and decoded usage;
  - live checks on local LM Studio or recorded responses;
  - `CFFIXED_USER_HOME` for data and a separate bundle id for app preferences;
  - no Keychain-touching tests.
- **Spending.** A paid probe under $20 is mentioned and run. Anything that surprises stops and asks.

## Status (2026-11-06): Phase 0 and Phase 1 built, on branch `caching`

| Item | Commit | What went in | Differs from the plan / not done |
|---|---|---|---|
| 0 | 4c429c8 | `PromptPrint` on each loop reply request's cost entry (`LLM/CacheLedger.swift`); `CacheMiss` with its cause, gap, lost tokens and dollars; a run's first request is checked against the session's last reply (`AgentConfig.previousReply`); `kurtkode cost cache [--since] [--compact-at 150k,200k] [--json]`; `CacheWatch`'s notice names the cause | Step 4 (importing Claude Code and Codex logs) not built; `spike/caching/cc_cache.py` still does that. First run on this Mac: 157 reply requests, 3 misses from an expired cache ($0.096), 8 server-side ($0.044); no session passed 150k |
| 1.1 | 88191c1 | `RunSettings.promptCacheTTL` auto/5m/1h (`cacheHour(interactive:)`); auto: an hour for app sessions and the live CLI, five minutes for subagents, `-p`, piped input, the eval's cascade; Settings → Prompt cache is a picker; the old switch on reads as 1h | — |
| 1.2 | e540f67 | Main runs offer every tool in every mode (`PermissionPolicy.offeredInEveryMode`); plan mode refuses a write when it's called (`modeRefusal`), `present_plan` outside plan mode is refused; an approved plan no longer changes the tool list | Subagents keep the mode-filtered list (`sameToolsInEveryMode = false`). A mode switch *between turns* still changes the system prompt (`Prompts/mode.md` is rendered into it), so it still loses the system prompt and history, not the tools; moving the mode rules into a message would also change the eval's prompt, left for a decision. MCP: the tool list was already fixed within a run; a server that connects between runs still changes it. Not checked: refusal counts on a small local model in plan mode |
| 1.3 | 12591d0 | `ChatRequest.cacheKey`: the session id (subagents `kind:session`) as OpenAI's `prompt_cache_key` and OpenRouter's `session_id`, on replies, summaries and the rating side request; pool editor note on provider order | `prompt_cache_retention: "24h"` dropped: per OpenAI's docs it is already the default without zero data retention |
| 1.4 | 1e33534 | `CacheWarmup`: a fan-out's runs of one kind on one hosted model wait until the first has started streaming, or 5 s | — |
| 1.5 | 12591d0 | `ChatRequest.oneOff` on titles, commit messages, side questions, the skill router, grades and reviews (and the summary's plain fallback): explicit caching with no breakpoints on GPT-5.6+, no breakpoints for Claude through OpenRouter, no automatic breakpoint on native Claude | A long fixed system prompt (≥6,000 bytes: a grader's, a reviewer's) stays cached on native Claude, so back-to-back gradings share it |
| 1.6 | 1417d88 | The profile editor's reasoning picker notes that changing it costs the cache on hosted models; the ledger names `effort` misses | No "≈$X" at the change: effort is set per model profile, outside any session |
| 1.7 | 1417d88 | `CacheLedger.coldResumeNote`: a session of 50k+ tokens past its cache lifetime gets the next message's cost, /compact's, and the saving per later request; the app shows it once on send (sending again goes ahead), the CLI on starting a resumed session and on /resume | — |

**Tests.** 21 new tests (`CacheLedgerTests`, `CacheRoutingTests`, `PromptCacheTTLTests`, `CacheWarmupTests`, one in
`CostTrackingTests`) and five plan-mode tests rewritten for 1.2. The full suite has 1,077 tests. Its failures are
the same kinds as on main before these changes, and none is in this work:
- process and timing tests that fail under the suite's parallel load and pass alone (a different few each run);
- `theShippedRealSetsAreConsistentWhenPresent`, whose fixtures aren't in a new worktree;
- the 7 known issues.

The app (`make build`) and the CLI build.

**Live check (2026-11-06, $0.017, 40 requests through OpenRouter).** Run with a debug build and the Keychain key,
in an isolated home (`CFFIXED_USER_HOME`), on a two-file project.

| Model | Results |
|---|---|
| deepseek-v4-flash-0731 | Every request carried `session_id` (the session's id), all returned 200. Both turns of a `-p … ; -c -p …` session stayed on one provider (Morph). The second turn's first request read 7,168 of 8,746 tokens from the cache. `kurtkode cost cache` on it: no misses, 93% read |
| openai/gpt-6-luna | The skill router's one-off request (1,783 tokens) was accepted with `prompt_cache_options` explicit and wrote nothing. The replies wrote their prefix once at 1.25× and read it after. List price matched OpenRouter's charge ($0.000798) |
| anthropic/claude-haiku-5.5 | With `-p`: 5-minute breakpoints, and a one-off router call that wrote nothing. Interactive (`--plain` in a pty): `ttl: 1h` sent and billed. A second interactive session read 9,103 tokens that the first left in the hour cache |

**Two bugs this found, both fixed:**
- OpenRouter reports Claude's cache writes without their lifetime, so hour writes were priced as five-minute ones ($0.0012 at list price, $0.0019 charged). `TurnRunner` now labels them from what the request asked for (`ChatClient.sendsHourCache`).
- OpenRouter's listing has one write price, which was used for the hour too. For Claude it is now 2× input (`RemotePrices.price`).

After both fixes, list price and charge agree: $0.0001588 against $0.00015883.

**Not checked live:**
- OpenAI's own API (`prompt_cache_key`): no endpoint is set up.
- Native Anthropic: the account has no credit.
- Gemini: none of the new fields go there.

## Phase 0: the cache ledger (ready, do first)

**R11, the part needed to measure everything else.**

1. **Miss causes.** Classify every request with at least 8k prompt tokens whose cache share fell, using the
   previous request of the same run and model. Causes:
   - `ttl`: the gap is longer than the TTL used;
   - `prefix`: the first differing byte found by the existing `WireDiff`, reported as tools, system or message *n*;
   - `model` or `effort` switch;
   - `compaction`;
   - `provider`: the OpenRouter provider changed (the stream's `provider` event is already decoded).

   Store the cause on the `CostEntry` (a new optional `cacheMiss` field). `cost report --by miss` sums the dollars
   lost to each cause.
2. **Gap statistics.** Record per session the gaps between a turn's last request and the next turn's first. These
   decide R2 and R5.
3. **What-if for TTL and compaction threshold.** `kurtkode cost whatif --ttl 1h|5m` and `--compact-at 200k` reprice
   recorded sessions. Use the same arithmetic as `spike/caching/ttl_cf.py`, and for compaction the model in the
   report's section 5.
4. **(Optional) Claude Code and Codex logs as a baseline.** `kurtkode cost import --claude-code` and `--codex` read
   `~/.claude/projects` and `~/.codex/sessions` into a separate report group, so kurtkode's sessions can be compared
   with Claude Code's on the same machine. `spike/caching/cc_cache.py` is the parser.

- **Where:** `Agent/Spending.swift` (`CacheWatch` becomes the classifier), `LLM/CostEntry.swift`,
  `Debug/SessionTimeline.swift` (WireDiff), `DebugCommands`.
- **Tests:** a recorded session with one instance of each cause.
- **Effort:** M. **Cost:** none.

## Phase 1: ready changes

These touch different files and can go in any order or in parallel.

### 1.1 TTL policy: 1 hour where people pause (R2)

Replace `promptCacheHour: Bool` with `promptCacheTTL: auto | 5m | 1h` (default `auto`; an old `true` reads as
`1h`).

`auto` gives 1 hour to requests of an **interactive main run**: the app, or the live CLI, but not `-p`, piped input
or eval. It gives 5 minutes to:
- subagents;
- summaries;
- side calls (titles, commit messages, router, judges, reviews);
- eval.

This is Claude Code's policy. Apply it in `AnthropicWire.encodeRequest` and in `WireFormat.withCacheBreakpoints` (the
OpenRouter Claude path). Only one TTL is used within a request, so Anthropic's rule that 1-hour entries must precede
5-minute ones doesn't arise.

- **Where:** `AgentLoop` (the run knows whether it is a subagent), `SessionRun`, `RunSettings`, `kurtkode-eval`,
  which passes `5m`.
- **Tests:** encoded bodies for each kind of request.
- **Expected effect:** −25% input cost on sessions with 5–60 minute pauses. That is the Claude Code data from this
  Mac; Phase 0's gap statistics will give kurtkode's own figure.
- **Effort:** S.

### 1.2 One tool list in every mode (R3)

Today `PermissionPolicy.offered` removes write tools in plan mode, and `AgentLoop.switchMode` swaps the list when a
plan is approved. Each swap rewrites the whole prompt: tools, system and history.

Change:
- **Offer every tool in every mode.** Enforce plan mode in the permission check instead: a write tool called in plan
  mode is refused with "Plan mode: present the plan with `present_plan` first; nothing is changed until it's
  approved."
- **Offer `present_plan` always.** Outside plan mode it answers that there is no plan to approve and the work can go
  ahead.
- **Background tools** (`bash_output`, `kill_shell`) are offered whenever bash is, which is already the case.
- **The mode** goes into the prompt as a note in the next user or tool message, never into the system prompt.

**MCP.** Freeze the tool list at a run's first request. A server that connects later contributes its tools from the
next run, with a notice. Whether to use the inline-tools beta for this is item 4.5.

- **Where:** `Agent/Permissions.swift`, `AgentLoop.switchMode`, `MCP/MCPHub.swift`, and the plan-mode prompt text in
  `Prompts`.
- **Tests:**
  - the `tools` array is byte-identical before and after `switchMode`;
  - a write in plan mode is refused and not run;
  - the eval's tool list doesn't change, because the eval doesn't use plan mode.
- **Risk:** small models may try writes in plan mode more often, since they now see the tools.
  - **Check:** count plan-mode refusals in the functional tests' plan scenarios (FUNCTIONAL_TESTS.md) on qwen3-coder
    and Haiku.
  - **Fallback if it's bad:** keep the filtered list in plan mode for local models only, where the cache costs
    nothing.
- **Effort:** S–M.

### 1.3 Cache keys and provider stickiness (R4)

**OpenAI** (`api.openai.com` and Azure; `WireFormat.encodeRequest` already knows the host):
- `prompt_cache_key`:
  - the session id for the main run;
  - `"<agent kind>:<parent session id>"` for subagents, as Codex does;
  - the purpose plus the session id for side calls that repeat.
- `prompt_cache_retention: "24h"` on gpt-5.x models up to 5.5, the documented list. It is free there.
- Nothing for GPT-5.6 and later, which use the new write pricing (see 1.5).

**OpenRouter:** a body `session_id` (the same value as the key) on every request, for every model. OpenRouter keeps
requests on one provider for 60 minutes of inactivity, which is the fix for COST_FLOOR's "deepseek 2.4× dearer by
provider routing".

**Provider pins:** pins that use `order` disable stickiness. Say so in the pool editor's provider field; `only` or
`ignore` keep it.

- **Where:** `LLM/WireFormat.swift`, `ChatRequest` (a `cacheKey` field set by `AgentLoop`), and
  `Models/PoolEditing` for the note.
- **Tests:** encoded bodies.
- **Live check:** two bank tasks on OpenRouter deepseek-off. The second run's first request reads the cache, and the
  provider is the same in both. About $0.01.
- **Effort:** S.

### 1.4 Warm the cache before fanning out (R7)

When one reply makes several `task` calls (`parallelTasks`, `AgentLoop.swift:1084`), group them by agent kind and
model. In each group:
1. Start the first.
2. Start the rest when its stream's first event arrives, or after 5 seconds, whichever is sooner.

An Anthropic cache entry is readable only after the first response has started. Claude Code holds siblings up to 5
seconds for this reason.

`max_tokens: 0` pre-warming is not needed: the first sibling does the warming as part of its real work.

- **Where:** `AgentLoop` (the parallel `task` branch) and `Subagents`.
- **Tests:** a mock client that records start times and the requests' cache usage.
- **Expected effect:** (N−1) × the shared prefix's write per fan-out: 2–6.5k tokens each.
- **Effort:** S.

### 1.5 No cache writes for one-off calls (R8)

On GPT-5.6 and later, a cache write costs 1.25×. A call that is never repeated should send
`prompt_cache_options: {"mode": "explicit"}` with no breakpoints. That turns caching off.

These purposes are single-shot:
- titles;
- commit messages;
- judge and grade;
- review;
- the skill router;
- calibration.

Summaries are **not** single-shot: they read the run's cache.

On Anthropic, the same calls send no `cache_control` when they are known not to repeat.

- **Where:** `ChatRequest` (a `cacheMode` field set from the cost entry's purpose), `WireFormat`, `AnthropicWire`.
- **Effect:** −20% on those calls on GPT-5.6+, and the 1.25×/2× write premium avoided on Anthropic side calls.
- **Effort:** S.

### 1.6 Price the switches that break the cache (R9)

A change of reasoning effort mid-session invalidates the message cache, like a model switch. Show "≈$X" for it with
`PriceList.switchCost`, as model switches already do.

An image added to a long Anthropic session invalidates the tools and system blocks. That is small (they are a few
thousand tokens), so it gets no notice.

- **Where:** the effort control in the app and CLI, `PriceList.switchNote`.
- **Effort:** S.

### 1.7 Resuming a cold session, priced (R5, the notice)

When a session's next request would come after its TTL, and its prompt is over 50k tokens, show what that request
will cost. Give both numbers:
- continue: a rewrite of the whole prompt at the write rate;
- `/compact` first: an uncached read and a summary, then a small write.

Offer `/compact` or a new session. This is Claude Code's `/clear` nudge, with prices.

- **Where:** `SessionRun` (the time of the last request is in the cost entries), app composer, CLI status line.
- **Effort:** S.

## Phase 2: cost-aware compaction (R1)

The build is ready. The default is gated on measurement.

**Build.** `ContextBudget` gains a cost threshold:

    T* = S + √(2·K·g / r)

- r and w are the model's read and write multipliers, from `PriceList`.
- S is the prompt size the last compaction plan predicted (`Compactor.plan`).
- g is the run's mean tokens added per step.
- K is w·S plus the summary's output priced at the model's output/input ratio.

Compaction triggers at `min(compactAt × limit, T*)`. Local models skip T*: their cache is free and re-processing is
what's slow.

The setting is "Compact for cost: auto / off / N k". It ships **off** until the experiment says otherwise. The Context
window display shows the threshold in use and why.

- **Where:** `Agent/Context.swift`, `LLM/PriceList.swift` (multipliers by model), the Settings Context pane.
- **Tests:** the formula against hand arithmetic, and that a local model ignores it.

**Gate: the experiment.** Compaction is lossy, and the question is whether earlier compaction costs passes or steps.

- **Task.** Long sessions: 8–10 related requests in one session over a real repository (real4's repositories),
  scripted with `-p --resume`. Each session must reach 300k+ tokens.
- **Arms.** Compact at 150k, 200k, and the current 70%. Models: Haiku 5.5 and Sonnet 5.5.
- **Measure.**
  - the gold checks on each request;
  - steps;
  - $ per session;
  - cache share.
- **Cost.** About $10–15, mostly on the Sonnet arm. I will state the figure before running it.
- **Decision rule.** Ship `auto` as the default if the pass rate is within one task of the 70% arm and $ per session
  falls by at least 20%.

**Effort:** M (build), M (experiment).

## Phase 3: the ChatGPT plan as a backend

**Status:** researched today from OpenAI's documentation at
https://developers.openai.com/siwc/token-sharing-open-source (all its pages) and the Help Center article
https://help.openai.com/en/articles/20001542.

### What OpenAI documents

**Eligibility**
- "ChatGPT plan usage is available to all open-source partners", and "supported open-source tools remain available to
  all ChatGPT users".
- Registration is self-serve. No client secret and no partner API key are needed.
- Paid or remotely hosted apps must fill in an interest form. Kurtkode is local.

**Accounting**
- Requests count toward the plan's "ChatGPT Work and Codex usage".
- Plus has a five-hour limit shared across all apps. Pro has none.
- The user can set a weekly cap per app in ChatGPT Settings → Usage.
- Credits after the plan limit are opt-in.
- OpenAI never switches billing silently.
- "Usage rates may differ between an app and ChatGPT." How cached tokens count is not stated.

**Sign-in: OAuth with PKCE through the system browser**
- Authorize at `https://auth.openai.com/api/accounts/authorize`.
- First sign-in sends `client_id=dynamic_agent_client`, `agent_name_hint=kurtkode` and `ext_agent_host_id`. The host
  id is a `urn:uuid:` value made once per host and kept.
- Scopes: `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`.
- `resource=https://api.openai.com/v1`.
- Loopback redirect `http://127.0.0.1:<port>/auth/callback`. Only the port may vary, and `localhost` is not accepted.
- The callback returns the issued `client_id` (`oaiapp_…`). Save it per account and reuse it after that.
- Exchange the code at `https://auth.openai.com/api/accounts/oauth/token`.

**Validation**
- Verify the ID token against OpenAI's JWKS: issuer, audience (the issued client id), expiry, nonce.
- Check that `chatgpt.tokens.use.direct` was granted. Without it, sign-in works but plan use is off, and the user
  needs a choice of another billing path.

**Tokens**
- Access tokens last 1 hour. Refresh tokens last 30 days and rotate on every refresh, so refreshes must be serialized
  across processes.
- Sign-out revokes at the `revocation_endpoint` from `https://auth.openai.com/.well-known/openid-configuration`.
- Credentials are stored owner-only and never logged.

**Inference**
- `POST https://api.openai.com/v1/responses` with the bearer token, `store:false` and `stream:true`.
- Success is `response.completed`. A usage-limit error can arrive mid-stream as `response.failed`.
- Models come from `GET /v1/models` with the same token, filtered to `visibility == "list"`.

**Unsupported on this route**
- Fields: `max_output_tokens`, `temperature`, `top_p`, `prompt_cache_retention`, `previous_response_id` (over HTTP),
  `metadata`, `user`, `safety_identifier`, `truncation`, `background`.
- `{"role":"system"}` items. Use `instructions` or developer messages.
- Hosted tools other than web search.

Function tools must be grouped in **namespaces** or sent as `additional_tools` items.

**Errors.** Each `subscription_sharing_*` code has a defined response. For example, `usage_limit_exceeded` (429) means
stop and link to Settings → Usage, and `unsupported_capability` (400) means remove `error.param` and don't retry.

**UI rules**
- The sign-in button reads "Continue with ChatGPT".
- A one-time "You're using your ChatGPT plan" notice.
- "Using ChatGPT plan" with a Manage usage link near the model picker.
- A usage-limit modal with Manage usage as its main action.

**The Codex app-server alternative.** `codex app-server` with `model_provider` pointed at `/v1/responses` and the
token in an environment variable also works. It would run Codex's agent loop in place of kurtkode's, so it is not the
path for the main loop.

### 3.1 A Responses API wire format (ready; useful beyond the plan)

`WireAPI.responses`, a new `LLM/ResponsesWire.swift`, beside `AnthropicWire` and `GeminiWire`.

**Encoder**
- The system prompt goes in `instructions`. The volatile tail goes as a developer message after it (see 4.1).
- History becomes `input` items:
  - `message`;
  - `function_call` and `function_call_output` (by `call_id`);
  - `reasoning` items with `encrypted_content`, kept verbatim in `NativeContent`, as thinking blocks already are.
- `include: ["reasoning.encrypted_content"]`, `store: false`, `stream: true`.
- `reasoning: {effort}` and `prompt_cache_key` (1.3).
- Tools grouped in a `namespace`. The exact schema is the gate below.
- On the plan route, the unsupported fields are left out: the output cap becomes the loop's own wall-clock and step
  limits.

**Decoder**
- SSE events: `response.output_text.delta`, `response.output_item.added/done`, `response.function_call_arguments.delta`,
  `response.reasoning_summary_text.delta`.
- `response.completed` carries usage: `input_tokens_details.cached_tokens` and `cache_write_tokens`, and
  `output_tokens_details.reasoning_tokens`.
- `response.failed` and `response.incomplete`.

**Also with an API key:** `api.openai.com` with an API key can use this wire instead of Chat Completions. It keeps
reasoning items, which Chat Completions drops on every turn, so it caches better for reasoning models.

- **Tests:** encode and decode against recorded streams. Use the API-key route on a cheap model, gpt-6-luna, for the
  first recordings: under $0.05.
- **Effort:** M.

**Gate (small):** the namespace schema for function tools.
- Read `codex-rs` (its requests send `{"type":"namespace","name":"functions","tools":[…]}`, as seen in
  `~/.codex/sessions`).
- Confirm with one request on the plan route.

### 3.2 Sign-in and tokens (ready)

**`Endpoints/ChatGPTPlanAuth.swift`**
- The PKCE flow above.
- A loopback listener on 127.0.0.1, port 1455 or the next free one.
- ID-token validation with the JWKS (CryptoKit RS256 via `SecKey`).
- Scope check, refresh and revocation.

**Storage**
- The token record goes in the Keychain, the same place API keys go (`Endpoints/Keychain.swift`), as one item per
  issued client id.
- The host id goes in `~/Library/Application Support/kurtkode/` and is not secret.

**Refresh**
- Done under the existing `locks/` directory's file lock, because the app and the CLI can both be running and the
  refresh token rotates.
- An unusable refresh token (`invalid_grant`, `refresh_token_reused`, …) leads to signing in again with the saved
  client id.

**Sign-out** revokes first, then clears, and keeps the client id and host id.

- **Tests:** the URL builder, PKCE, the callback parser and the token-record round trip, with no network and no
  Keychain; an in-memory store goes behind the protocol.
- **Live:** one sign-in by the user. It needs their browser and consent, so the user does it.
- **Effort:** M.

### 3.3 The endpoint, prices and routing (ready, with one open choice)

**Endpoint**
- A new endpoint kind, "ChatGPT plan", using the `responses` wire with `https://api.openai.com/v1`.
- Its credential comes from 3.2.
- Its model list comes from `/v1/models` with the token.

**Cost records**
- `CostEntry` gains `billing: .plan`: charged $0, with the list price kept as "API-equivalent".
- `cost report` shows both columns, so the plan's value is visible.
- The cost meter counts plan requests at $0 against the run and day limits.

**Routing**
- The pool gains the plan's models as entries with `billing: plan`. The cost router treats their marginal price as
  zero while the plan has room.
- It falls back by the pool's order only when the user has said so: OpenAI won't switch billing silently, and neither
  should kurtkode. On a usage-limit error the run stops and asks: "ChatGPT plan limit reached (Manage usage). Continue
  on <next pool entry> at ≈$X?"
- **Open choice for the user:** whether a signed-in plan becomes the default main model, or a pool entry the user
  chooses.

**Errors.** Each `subscription_sharing_*` code maps to its documented action, in `ChatClient`'s error mapping.

- **Effort:** M.

### 3.4 Interface (ready)

**App**
- "Continue with ChatGPT" in Settings → Endpoints and in the first-run sheet.
- The one-time "You're using your ChatGPT plan" notice.
- "Using ChatGPT plan · Manage usage" by the model picker when the selected model is on the plan.
- The usage-limit sheet.

**CLI**
- `kurtkode endpoint login chatgpt` opens the browser and waits on the loopback.
- `kurtkode endpoint logout chatgpt` and `kurtkode doctor` report the account, scopes and token expiry.
- The status line shows "ChatGPT plan".

- **Effort:** S–M.

### 3.5 Gates for Phase 3: probes on the user's own plan

These run after 3.1 and 3.2 and cost nothing in dollars, only plan usage.

| Question | Probe |
|---|---|
| Q1. Is kurtkode eligible as it is? | The docs say open-source and locally hosted tools. Kurtkode runs locally; is its source public? If registration or the first request is refused, `subscription_sharing_user_not_eligible` or `route_not_supported` will say so. **The user's call:** register it as "kurtkode" from a private build, or publish the source first |
| Q2. Does `prompt_cache_key` work on this route, and are `cached_tokens` reported? | The same 10k-token prompt twice within a minute; compare usage |
| Q3. How does the plan meter weigh cached tokens? | Before and after 20 cached requests and 20 uncached ones of the same size, read Settings → Usage's percentage for kurtkode. This is the single fact that decides whether the cache levers matter on the plan at all |
| Q4. Does the route send rate-limit or usage headers, as Codex's ChatGPT backend does (`x-codex-*-used-percent`)? | Log the response headers of a probe. If there are any, the router can see remaining quota; if not, only the 429 tells |
| Q5. Which models and reasoning efforts does the user's account get? | `/v1/models` with the token |

**Not to do on the plan route:**
- don't use ChatGPT's `backend-api` endpoints (the docs forbid it);
- don't reuse Codex's own client id;
- don't route other people's requests through one user's plan.

## Phase 4: gated items (research or probe first)

| # | Item | Gate | Cost | Then |
|---|---|---|---|---|
| 4.1 | **The volatile facts out of the system text for Gemini, OpenAI Chat and Responses** (R6), so tools and the stable prompt make a prefix that survives across runs | Probe: two runs of one bank task in two folders on gemini-3.8-flash and an OpenAI model; read the second run's first-request `cachedContentTokenCount` / `cached_tokens` with the facts in the system text and in the first user message | < $0.05 | If the move raises cross-run reads, move the facts into the first user message for those APIs. Anthropic stays as it is, since its breakpoint already handles it |
| 4.2 | **Idle compaction before the 1-hour cache expires** (R5, second half) | Phase 0's gap statistics: how often do sessions over 100k resume after more than an hour? | free | Build if it happens weekly or more: compact at ~55 minutes of idle while the cache is warm |
| 4.3 | **Cheaper service tiers for unattended work** (R10). OpenAI Flex (`service_tier: "flex"`, −50%, slower, can return 429 "resource unavailable") for background subagents and eval. Anthropic Batch for `--review-sim`, judging and replay in the eval | Read the Flex guide's failure behavior; check whether OpenRouter exposes Flex or DeepSeek's off-peak price | free | Flex as a per-role option in the pool; Batch inside `kurtkode-eval` for single-shot work |
| 4.4 | **Fork subagents that inherit the parent's prefix** (R12) | Delegation scenarios (`eval-results/delegation-note`): fork against a fresh subagent on 10 tasks whose answer needs the parent's context | ≈$2 | A `context: fork` option on `task` if the fork is cheaper at an equal pass rate |
| 4.5 | **MCP tools without breaking the cache**: Anthropic `defer_loading` tool search and the `inline-tools-2026-09-15` beta; OpenAI `additional_tools` input items | Read both providers' docs on these; check which models take them | free | Replaces 1.2's "next run" rule for late MCP servers |
| 4.6 | **Gemini 4's 2,050-token tail.** Steps that add fewer tokens reprocess the last 2,050 at full price | From recorded gemini-4-argon cost entries: the share of steps under 2,050 new tokens and the dollars lost | free | If material, raise the minimum work per Gemini step (batch small tool results), or prefer another model for chatty loops |

## Order and dependencies

1. **Phase 0** first. It is small, and every later change is judged by it.
2. **Phase 1** items 1.1–1.7 next, in any order. They touch different files, except that 1.3 and 1.5 both touch
   `WireFormat`, so do those two together.
3. **Phase 3.1–3.2** can start alongside Phase 1, in new files. 3.3–3.4 follow, then the 3.5 probes with the user.
4. **Phase 2's build** can come any time. Its experiment comes after 1.1, so the experiment runs with the TTL policy
   that will ship.
5. **Phase 4** items run as their gates are met.

## Expected effect, overall

| Change | Where it saves | Size |
|---|---|---|
| 1.1 TTL policy | Anthropic sessions with pauses | about −25% input cost (Claude Code data) |
| 1.2 Constant tools | sessions that use plan mode | a full-prompt rewrite per mode switch |
| 1.3 Keys and stickiness | OpenRouter non-Claude models; OpenAI direct | restores cross-request reads lost to provider hops (the 2.4× case) |
| 1.4, 1.5, 1.6, 1.7 | fan-outs, side calls, switches, resumes | small each; 1.7 avoids the most expensive single request |
| 2 Cost-aware compaction | long sessions | −30–50% input cost, if quality holds |
| 3 ChatGPT plan | everything routed to it | marginal $0 within the plan's limits; the API-equivalent value is what `cost report` will show |

## Decisions (made 2026-11-06)

1. **Registration (Phase 3, Q1).** Publish kurtkode's source as a **public** repository at
   github.com/bollacker/kurtkode (it exists, empty) before registering it with OpenAI.
   - First, scan the whole history and working tree for keys, the signing keystore, session logs and personal
     paths.
   - The user sees what would go up and approves the push.
2. **The plan as default (3.3).** Run the eval sets on the plan's models first. That costs plan usage, not dollars.
   If they pass about as well as Haiku and Sonnet, the plan becomes the default for main runs and subagents while it
   has room.
3. **At the plan's limit (3.3).** Continue automatically on the next pool model, within the run's dollar limit
   ($2 by default), and say so. The user chose this over asking each time; OpenAI's own rule is only that the app
   must not switch billing *silently*.
4. **The user's plan: ChatGPT Plus.**
   - The five-hour limit is shared with ChatGPT and Codex, so routing to the plan needs a fallback (decision 3)
     and the router should expect 429s.
   - Q4 (usage headers) matters more on Plus.
5. **Phase 2.** Build the cost-aware threshold and run the experiment, under a $15 cap. The figure is confirmed
   before it starts.
6. **Mode rules (1.2 leftover).** Move the mode's rules out of the system prompt into a note after the user's
   message, so a mode switch between turns keeps the cache. The eval's system prompt changes once; note it beside
   the commit, as earlier prompt changes were.
