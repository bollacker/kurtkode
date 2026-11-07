# Prompt caching: what Claude Code and Codex do, what the APIs offer, what kurtkode should do

2026-11-06. Research for the next cost step after model choice. Sources: the vendors' docs and engineering posts
(URLs inline), community reports (marked *community*), kurtkode's code, and this Mac's own Claude Code and Codex logs
(section 1, measured). Prices are the vendors' pages as read today; several pages describe models newer than the
research agents' training, so anything marked *unverified* needs a check before code depends on it.

## Bottom line

1. **The hypothesis holds, with one correction.** Agentic coding is almost all re-reading. On this Mac, 98.2% of the
   7.5 billion prompt tokens Claude Code sent since August were cache reads. Output was 0.4% of tokens.

   Priced at the API's list rates, those three months cost about **$4,100**. With no caching, the same tokens would cost
   about **$36,900**. Cache reads are listed at 2.5–10% of the input price and need no prefill compute, so they are
   cheap for the provider too. Anthropic's own engineers say the hit rate is what lets them set subscription limits
   generously.

   The correction: this saving is not hidden on the server. The API offers the same discount to anyone who keeps the
   prefix stable. Claude Code's real advantages over a naive client are simpler:
   - it never breaks the prefix;
   - its main conversation uses a 1-hour cache on subscriptions;
   - its quota appears to weigh tokens differently from the price list (*community* fits put cache reads at about 0.1×).
2. **For kurtkode the hit rate is mostly solved. The size of what gets re-read is not.** Kurtkode already reaches
   91–96% cache reads within a run, and since session 18 its prefix survives across runs (COST_AUDIT.md section 9).

   What remains is:
   - **How large the context is allowed to grow.** On this Mac, 71% of Claude Code's cost came from requests whose
     prompt was over 200k tokens. Kurtkode compacts at 70% of the context window, which is 700k on a 1M model. At the
     price ratios below, compacting near 150–200k tokens is roughly 35–50% cheaper on input.
   - **What happens when the user pauses.** A 5-minute cache, kurtkode's default, would have cost 33% more on this
     Mac's main threads than the 1-hour cache Claude Code used.
   - **A handful of prefix breakers and missing parameters**: plan mode changes the tool list; no `prompt_cache_key`;
     no OpenRouter `session_id`; the run-varying facts sit ahead of the tools on Gemini and OpenAI.
3. **Ranked recommendations are in section 6.** The top four are small changes:
   - a cost-aware compaction threshold;
   - the 1-hour TTL on for interactive main sessions;
   - a constant tool list in plan mode;
   - cache keys and session ids for OpenAI and OpenRouter.

   The biggest lever of all, a subscription backend, is open only on OpenAI's side (section 7).

## 1. What this Mac's logs show (measured)

**Claude Code.** Scripts: `spike/caching/cc_cache.py` and `spike/caching/ttl_cf.py`, which read
`~/.claude/projects/**/*.jsonl`; run them from `spike/caching`. The logs cover 292 transcripts, 2026-08-05 to 11-06, 25,986 requests, and
7,522M prompt tokens.

| | Requests | Avg prompt | Cache read | Cache write | Write TTL |
|---|---|---|---|---|---|
| Main conversation (Opus 5.5) | 9,441 | 370k | 98.5% | 1.5% | 100% 1 hour |
| Main, all models | 21,500 | 290–370k | 97.7–99.0% | 1–2% | 100% 1 hour |
| Subagents, all models | 4,475 | 90–140k | 91–96% | 4–9% | 100% 5 minutes |

**API-equivalent cost.** Priced at kurtkode's own `PriceList` rates, the three months come to $4,101:

| Part | Share |
|---|---|
| Cache reads | 52% |
| 1-hour writes | 27% |
| 5-minute writes | 4% |
| Output | 17% |
| Uncached input | about 0% |

The same tokens with no caching would cost $36,855. Whatever plan this account was on, that is about $1,350 a month
of API value.

**Idle gaps (main conversation).** The cache survives gaps of up to an hour and is lost after that:

| Gap before the request | Requests | Read share of the prompt |
|---|---|---|
| Under 1 minute | 18,689 | 99.3% |
| 1–5 minutes | 1,855 | 98.1% |
| 5–60 minutes | 632 | 99.2% |
| Over an hour | 192 | 15% (the rest rewritten) |

**TTL counterfactual (main conversation, input side).**

| Cache policy | Cost |
|---|---|
| Actual, 1-hour TTL | $3,105 |
| A 5-minute TTL (the 632 requests after 5–60 minute gaps rewrite their whole prompt; other writes at 1.25×) | $4,119 (+33%) |
| A 5-minute TTL with keepalive pings every 270 s (an hour of wasted pings for each session the user left) | $3,074 |

So on Anthropic the 1-hour TTL is as good as pinging and sends no background traffic.

**Where the money is, by prompt size** (share of cost):

| Prompt size | Share of cost |
|---|---|
| ≤100k | 9% |
| 100–200k | 20% |
| 200–400k | 35% |
| 400–700k | 26% |
| Over 700k | 10% |

**Codex.** Four sessions in `~/.codex/sessions`, all on gpt-6.1-sol. 86–96% of input tokens were cached. The largest
session had 4.07M input tokens, 3.93M of them cached.

**Kurtkode's own eval data** (COST_AUDIT.md):
- Within-run cache reads are 91–96% for every hosted model.
- Before session 18, cross-run reads were 0 of 480 Haiku runs.
- After the prefix fix, 8 of 10 first requests read the cached prefix, at −37% a run on the bank tasks.

## 2. How Claude Code and Codex do it

**Claude Code** (https://code.claude.com/docs/en/prompt-caching, and Thariq Shihipar's "Prompt caching is everything",
https://claude.dev/blog/lessons-from-building-claude-code-prompt-caching-is-everything/):

- **Order.** Static system prompt and tools first, which are cached globally. Then CLAUDE.md and memory, then the
  session's context, then the conversation. Anything that changes goes in later messages as `<system-reminder>` text,
  never into the system prompt.
- **Never changes mid-session:**
  - The model. Cheaper models are used through subagents with a hand-off message instead.
  - The tool list. Plan mode is a pair of tools (Enter/ExitPlanMode) that are always present. MCP tools go out as
    `defer_loading` stubs, and the list from the first request is kept for the conversation.
  - Effort and fast mode. Changing them is documented as a cache break.
- **The team treats the hit rate as uptime**: alerts, and a SEV when it drops. The post names the breakages they had:
  a timestamp in the static prompt, shuffled tool order, changed tool parameters.
- **Compaction is a "cache-safe fork".** It sends the same system prompt, tools and history plus the summary
  instruction, so the summary call reads the cache. Kurtkode already does this (`Compactor.compactAll`).

  Since v2.1.290, *idle compaction* can compact a 1-hour session before its cache expires. The most expensive case
  the docs name is compacting a resumed old session, which re-reads everything uncached.
- **TTL.** The main conversation gets 1 hour on a subscription within plan limits. Everything else gets 5 minutes:
  - API keys;
  - usage credits;
  - subagents, compaction and titles.

  Settings: `CLAUDE_CODE_PROMPT_CACHE_TTL`, `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL`, `ENABLE_PROMPT_CACHING_1H`.
  *Community* log analyses show Anthropic moved the subscription TTL between 1 hour and 5 minutes several times in
  early 2026 (https://lilting.ch/en/articles/claude-code-cache-ttl-quota-exhaustion). The docs now state 1 hour.
- **Subagents.** A fresh subagent has its own system prompt and tools, so it does not read the parent's cache. A
  *fork* inherits the parent's prefix and reads it. Workflow fan-outs hold every agent but the first for up to 5 s, so
  the rest read the first agent's cache.
- **Context size.** Boris Cherny, on issue #45756 (https://github.com/anthropics/claude-code/issues/45756), said
  stale resumes of 1M-token sessions are the expensive case. Anthropic added `/clear` nudges, is considering a 400k
  default window, and offers `CLAUDE_CODE_AUTO_COMPACT_WINDOW`.
- **How cache reads count against plan limits is not published.** *Community* fits over tens of thousands of requests
  put it near 0.1×, the API ratio. Anthropic's ITPM rate limit does not count cache reads at all
  (https://platform.claude.com/docs/en/api/rate-limits).

**Codex CLI** (source: `openai/codex` `codex-rs/core/src/client.rs`):

- `prompt_cache_key` is a session-derived key on every request. Internal sub-requests use
  `"{source}:{parent_thread_id}"`.
- `store: false` always, and it always asks for `reasoning.encrypted_content`, so reasoning items go back verbatim.
- History is append-only. Over WebSocket it sends only the new tail with `previous_response_id` when the request
  strictly extends the last one.
- Compaction uses `/responses/compact`, which returns an opaque encrypted item, and costs one cache miss.
- Known trouble: issue #20301 (https://github.com/openai/codex/issues/20301) reported near-0% hits on gpt-5.5 against
  90%+ on 5.4. It was reopened and is still open. A proxy that replaced `prompt_cache_key` with a fresh UUID per
  request was estimated at 5–10× the cost (*community*).

**Others:**
- **Aider** has `--cache-keepalive-pings N`: a ping every ~295 s, up to N times after each message.
- **opencode** has opt-in "warming": a "reply OK" request after 4 minutes idle, every 4 minutes for 30 minutes, or at
  90% of the model's TTL.
- **Mux** sets a per-workspace `prompt_cache_key`.
- The common rules across tools are the ones above: append-only history, static first, deterministic tool order,
  stable paths and keys, and no model or tool switches mid-session.

## 3. The levers, by provider

All from the providers' own docs unless marked.

### Anthropic

Sources: https://platform.claude.com/docs/en/build-with-claude/prompt-caching and the pricing page.

**Placement**
- *Automatic* caching (a top-level `cache_control`) moves the breakpoint forward as the conversation grows. Kurtkode
  uses it.
- At most 4 breakpoints, the automatic one included.
- Reads look back at most 20 block positions from a breakpoint. A run of tool_use or tool_result blocks counts as one
  position.

**Minimum prompt length**
- 512 tokens on the 5.x models.
- 1,024 on Sonnet 5, Opus 4.8 and earlier 4.x.
- 4,096 on Haiku 4.5 and Opus 4.5/4.6.

**TTL and price**

| | Multiple of base input |
|---|---|
| 5-minute write (default) | 1.25× |
| 1-hour write | 2× |
| Read, default | 0.1× |
| Read, Opus 5.5 and Sonnet 5.5 | 0.05× |
| Read, Fable 5.1 | 0.025× |

- A hit refreshes the TTL at no charge.
- Multipliers stack with the Batch discount (50%) and long-context pricing.
- With mixed TTLs, the 1-hour entries must come before the 5-minute ones.

**What invalidates the cache**
- The order is tools → system → messages, and a change invalidates its level and everything after it.
- Tool definitions: all three levels.
- `tool_choice`, or adding or removing images: tools and system.
- Thinking mode, budget and `effort`: messages at least.
- On the 5.x models, a mid-conversation `system` message does **not** invalidate anything.
- The `inline-tools-2026-09-15` beta adds tools through such a message without touching `tools`.

**Pre-warming**
- `max_tokens: 0` writes the cache with no output. It is refused for streaming, enabled thinking and inside batches.
- A cache entry is readable only once the first response has started, so fan out after that point.

**Context editing**
- `clear_tool_uses` clears old tool results on the server.
- Each clear costs a cache rewrite, and `clear_at_least` makes each clear worth it.
- Server-side compaction (`compact-2026-09-04`) exists. It recommends a breakpoint at the end of the system prompt so
  only the summary is rewritten.

**Isolation, limits, counting**
- The cache is per workspace.
- Cache reads don't count toward ITPM.
- `count_tokens` is free but uncached and only an estimate.

### OpenAI

Sources: https://developers.openai.com/api/docs/guides/prompt-caching and the pricing page.

**Before GPT-5.6 (gpt-5.5 and earlier)**
- Implicit caching from 1,024 tokens.
- Writes are free. Reads are about 0.1× (o3 0.25×).
- `prompt_cache_key` steers routing. Keep each key near 15 requests a minute or traffic spills to cold machines.
- `prompt_cache_retention: "24h"` is supported on gpt-5.x and 4.1. It is the default without zero data retention.

**GPT-5.6 and later**
- Writes now cost **1.25×** for the default 30 minutes, or 2.5× for 12 hours (Responses API only).
- Reads are 0.1×, and 0.05× on gpt-6.1 Sol and Terra.
- Explicit mode exists: `prompt_cache_options {mode, ttl, prewarm}` and `prompt_cache_breakpoint` on content blocks,
  with up to 4 writes. Explicit mode with no breakpoints turns caching off. That is now cheaper for one-off prompts,
  which would otherwise pay the write premium for nothing.

**Usage and limits**
- Usage reports `cached_tokens` and `cache_write_tokens`, broken down by TTL.
- Cached tokens **do** count toward TPM.

**What breaks the prefix**

OpenAI's guidance: don't change any of these mid-conversation:
- `model`
- `tools` (use `allowed_tools` or `tool_choice: "none"` instead)
- `parallel_tool_calls`
- `reasoning.effort`
- `text.verbosity`

**Responses API**
- `previous_response_id` bills the whole chain as input. Its caching behavior is not documented.
- Codex uses stateless `store:false` with encrypted reasoning.

**Flex and Batch**
- Both are about 50% off, with cached rates halved as well, so the discounts stack with caching.
- Flex is synchronous, so it works inside an agent loop.

### Google Gemini

Sources: https://aistudio.google.com/docs/caching and the pricing page.

**Implicit caching**
- On for 2.5 and later, with no write or storage charge.
- Minimums: 4,096 tokens on Gemini 4 Argon and 3.6/3.8 Flash; 2,048 on 2.5.
- Reads are 0.1× (Argon 0.05×).
- Put common content first and send similar prefixes close together in time.

**Gemini 4 Argon in agent loops**
- The whole previous request is reused only when the new request adds at least 2,050 tokens.
- Otherwise the last 2,050 tokens are reprocessed at the full input price. That is a fixed tax on every small step.

**Explicit caching**
- `cachedContents`, storage $0.50–4.50 per M tokens an hour. Not offered on Argon and later or in the Interactions
  API.
- TTL and minimum for generateContent: *unverified* (snippets say 1 hour by default).

**Introductory prices**
- Argon's and 3.8 Flash's prices rise on 2026-12-01 and 2027-01-01, and so do their cache reads. The kurtkode table
  already carries the `until` dates.

### OpenRouter

Source: https://openrouter.ai/docs/guides/best-practices/prompt-caching.

**Passthrough**
- `cache_control` for Anthropic (1-hour TTL included), Gemini and Qwen.
- Automatic caching for OpenAI, DeepSeek, Grok and Moonshot.

**Sticky routing**
- After a cached request, later requests go to the same provider.
- A body `session_id` (or `x-session-id`) makes it sticky from the first successful request, and keeps it for 60
  minutes of inactivity.
- Setting `provider.order` disables stickiness.

COST_FLOOR_RESULTS.md's finding that provider routing made deepseek 2.4× dearer a run is exactly what this addresses.

### DeepSeek, Grok, Moonshot

- **DeepSeek** has a disk cache that is on by default and kept for hours to days.
  - Hits cost about 0.02× of a miss (flash: $0.003 off-peak against $0.15).
  - Off-peak is half of peak. Peak is 01:00–04:00 and 06:00–10:00 UTC on weekdays.
- **Grok and Moonshot** (per OpenRouter): automatic caching, free writes, reads 0.25×.

### Summary table

| | Min tokens | TTL | Write | Read | Control |
|---|---|---|---|---|---|
| Anthropic | 512 (5.x) to 4,096 | 5 m / 1 h | 1.25× / 2× | 0.1× (0.05× Opus/Sonnet 5.5; 0.025× Fable 5.1) | `cache_control` (automatic or ≤4 blocks), `ttl`, `max_tokens:0` pre-warm |
| OpenAI ≤ 5.5 | ~1,024 | in-memory (5–60 m) / 24 h | free | ~0.1× | `prompt_cache_key`, `prompt_cache_retention` |
| OpenAI ≥ 5.6 | 1,024 | 30 m / 12 h | 1.25× / 2.5× | 0.1× (0.05× 6.1 Sol/Terra) | `prompt_cache_options`, `prompt_cache_breakpoint`, key |
| Gemini implicit | 2,048–4,096 | minutes, unstated | free | 0.1× (Argon 0.05×) | prefix order only; ≥2,050 new tokens a step on Argon |
| Gemini explicit (≤3.x) | unverified | 1 h default? | input + storage per hour | 0.1× | `cachedContents` |
| OpenRouter | per provider | per provider | per provider | per provider | `session_id`, `cache_control`; no `provider.order` |
| DeepSeek | none stated | hours–days | input price | ~0.02× | automatic; off-peak half price |

## 4. Where kurtkode stands

**Already done:**
- Automatic `cache_control` on native Anthropic.
- The system prompt split at `SystemPromptBuilder.volatileHeading`, with a breakpoint on the stable part, so tools
  and the stable prompt are cached across runs.
- `cache_control` breakpoints for Claude via OpenRouter.
- Deterministic JSON (`.sortedKeys` in `WireFormat`).
- The compaction summary placed in the volatile tail, so the stable prefix survives a compaction.
- Summary requests that reuse the run's prefix.
- Tool outputs trimmed only in rare large steps (`ContextBudget`'s comment says why).
- A 1-hour option (`promptCacheHour`, off by default).
- `CacheWatch`'s miss notice, and "≈$X to switch" before a model change.
- Per-request cache usage recorded for all three APIs.

**Gaps found reading the code:**

| # | Gap | Where | Effect |
|---|---|---|---|
| G1 | Compaction triggers at 70% of the model's window, so 700k on a 1M model, with no regard to price | `ContextBudget(compactAt: 0.7)` | every step re-reads up to 700k tokens; see section 5 |
| G2 | The 5-minute TTL by default for everything | `promptCacheHour = false` | a pause of 5–60 min rewrites the whole history (+33% on this Mac's Claude Code data) |
| G3 | Plan mode offers a different tool list; approving a plan mid-run swaps it (`switchMode`) | `PermissionPolicy.offered`, `AgentLoop.switchMode` | each switch invalidates tools, system and history: a full rewrite |
| G4 | No `prompt_cache_key` / `prompt_cache_retention` to OpenAI | `WireFormat.encodeRequest` | pre-5.6 models lose routing affinity and the free 24 h retention |
| G5 | No OpenRouter `session_id`; provider pins may use `provider.order` | `WireFormat`, pool provider pins | provider hopping loses the cache (deepseek 2.4× dearer, COST_FLOOR) |
| G6 | On Gemini and OpenAI Chat, the volatile facts sit at the end of the system text, which renders before the tools | `GeminiWire` `systemInstruction`; OpenAI system message | cross-run reuse probably stops before the tool list. Needs a probe, since the rendering order is the provider's |
| G7 | Parallel subagents of one kind start together | `Subagents` | each writes the same 2–6.5k-token prefix; only the first needed to |
| G8 | One-off side calls on GPT-5.6+ (skill router, titles, commit messages, judges, reviews) would pay the 1.25× write premium | `SkillRouter`, `ChatTitle`, `CommitMessage`, `Judging`, `Review` | 25% more on each such call, for a cache nobody reads |
| G9 | A change of reasoning effort mid-session breaks the message cache like a model switch, with no notice | `reasoningEffort` per request | silent rewrite |
| G10 | No idle handling: a session resumed after the TTL rewrites everything at the write rate with no warning | `SessionRun` | the most expensive single request in a session, unannounced |

## 5. The cost model that matters now

With hit rates above 95%, a step's input cost is about:

    r × (prompt so far)  +  w × (tokens new this step)  +  (compaction's cost) spread over the steps between compactions

Here r is the read multiplier (0.025–0.1) and w the write multiplier (1.25 or 2). The first term grows with the
context, so a session's cost grows with the square of its length until something shrinks the context.

A compaction costs:
- rewriting the compacted prompt (w × S);
- one cached read of everything (r × T);
- the summary's output.

Minimizing the average gives a cost-optimal compaction point of about **S + √(2·K·g / r)**, where S is the prompt
right after compaction, g the tokens a step adds, and K the compaction's cost in input-token units.

Assumptions: S = 40k, g = 5k a step (this Mac's Claude Code data averages about that), 1-hour writes, and a
4k-token summary priced at 5× input.

| Compact at | Read 0.05× (Opus/Sonnet 5.5): input cost a step | Read 0.1× (Haiku 4.5, GPT, Gemini) | Steps between compactions |
|---|---|---|---|
| 100k | 22.2k | 26.2k | 12 |
| 150k | 19.6k | **24.7k** | 22 |
| 200k | **19.4k** | 25.8k | 32 |
| 400k | 22.7k | 33.9k | 72 |
| 700k (kurtkode's 70% of 1M) | 29.5k | 48.3k | 132 |

Units are thousand-token equivalents at the base input price. 10k of each figure is the new tokens' write, which no
threshold changes.

The optimum is about 180k at a 0.05× read and about 140k at 0.1×. Compared with 700k, that is −34% and −49% of input
cost. It is flat between 150k and 250k, so a round 200k default loses little.

Two cautions:
1. Compaction is lossy, and a weaker continuation can cost more steps than it saves. That is the thing to measure
   (R1).
2. For a model with a short window, 70% may already be below the optimum. The rule should be the minimum of the two.

The same arithmetic says when to delegate. A subagent's reads come out of a 20–140k context instead of the parent's
300k. Kurtkode's delegation threshold (COST_AUDIT improvement 7) is the same lever seen from the other side.

## 6. Recommendations, ranked

Effort: S = a day or less, M = a few days.

| # | Change | Expected effect | Effort | How to measure |
|---|---|---|---|---|
| **R1** | **Cost-aware compaction.** Compact at `min(70% of window, cost-optimal T)`, with T from the formula and the model's read and write multipliers in `PriceList`. Expose it as "Compact at about N k tokens (cost)" with the window as the cap. Default about 200k for 0.05× readers and 150k for 0.1×. Keep the current threshold for local models, where the cache is free and re-processing is slow. | −30–50% input cost on long sessions; nothing on short ones | S–M | Replay or extend a real-sized task set (real4, a long session script) at 150k / 200k / 700k: cost, pass rate, steps. The pass rate is the risk |
| **R2** | **1-hour TTL for interactive main sessions on Anthropic, 5-minute for subagents, eval and `-p`.** This is Claude Code's policy. Also the OpenRouter Claude path. | −25% input cost on sessions with pauses (this Mac: $4,119 → $3,105) | S | `CacheWatch` misses after gaps; `cost report` cache share before and after |
| **R3** | **A constant tool list.** Offer every tool in every mode and enforce plan mode in the permission check (a refusal explaining plan mode), as Claude Code does. `present_plan` is always offered. For MCP, keep the first request's list for the session, and use `defer_loading` or the inline-tools beta where available. | Removes a full rewrite at every plan-mode entry and approval: about 1.25–2× of the whole prompt each time | S–M | A WireDiff of the requests around a plan approval: the tools must be byte-identical |
| **R4** | **OpenAI and OpenRouter parameters.** `prompt_cache_key` = session id (subagents `kind:parent`), `prompt_cache_retention: "24h"` on gpt-5.x ≤ 5.5, OpenRouter `session_id` on every request, and provider pins via `only`/`ignore` rather than `order` (check what the pool sends). | Restores provider stickiness (the deepseek 2.4× case) and free 24 h retention | S | Cross-run first-request cache reads on OpenRouter deepseek and ling; charge per run |
| **R5** | **Idle handling, priced.** When a session resumes after the TTL with more than ~50k tokens, say what the next request will cost and offer `/compact` or a fresh session first (Claude Code's `/clear` nudge). With the 1-hour TTL, optionally compact a large idle session at ~55 minutes while the cache is warm (Claude Code's idle compaction). Pings only for providers whose TTL can't be set (Gemini implicit, OpenAI in-memory), and then capped, as opencode does. | Avoids the single most expensive request of a session; how much depends on usage | S (notice), M (idle compaction) | Count resumes after gaps over 1 h in real sessions, and their first-request cost |
| **R6** | **Move the volatile facts into the first user message for Gemini and OpenAI Chat**, keeping the system text plus tools identical across runs. Probe first: two runs in two folders, then compare `cachedContentTokenCount` / `cached_tokens` on the second's first request. | Cross-run reuse of the tool list (several thousand tokens a run) on those APIs | S | The probe itself |
| **R7** | **Warm before fan-out.** Launch the first subagent of a kind, and start its siblings when its first streamed event arrives (Claude Code holds up to 5 s), or pre-warm with `max_tokens: 0` on Anthropic. | (N−1) × the shared prefix's write per fan-out; small, and free | S | First-request reads of the 2nd..Nth sibling |
| **R8** | **Caching off for one-off calls on GPT-5.6+** (explicit mode, no breakpoints) for the router, titles, commit messages, judges and reviews; on Anthropic, no `cache_control` on calls under the minimum or never repeated. | −20% on those calls | S | Cost entries by purpose |
| **R9** | **Price the invisible switches.** Show "≈$X" for reasoning-effort changes, as for model changes (G9). Keep images out of the prefix where possible (adding one invalidates tools and system on Anthropic). | Fewer surprise rewrites | S | — |
| **R10** | **Cheaper tiers that stack with caching for unattended work.** OpenAI Flex (−50%, synchronous) for background subagents and eval. Anthropic Batch (−50%, warm a 1-hour prefix first, then submit the rest) for grading, reviews and eval replays. DeepSeek off-peak (−50%) for scheduled eval runs. | −50% on that slice | M | Eval cost per run |
| **R11** | **A cache ledger in `cost report`.** For each miss, say why: TTL expiry (from the gap), prefix change (from `WireDiff` against the previous request), model or effort switch, compaction, or provider hop. Add a "what if" for TTL and compaction threshold over recorded sessions, like this report's scripts. Optionally import Claude Code and Codex logs into the same report as a baseline. | Makes every lever above measurable on the user's own work | M | — |
| **R12** | **Fork subagents.** A subagent that inherits the parent's prefix reads it at r instead of rediscovering context. That is cheaper than a fresh subagent only when the parent's context is what the task needs. Measure before shipping. | Unknown | M | Delegation scenarios with fork against fresh |

**What not to do.**
- **Don't trim or edit earlier messages a little at a time.** Every recommendation above keeps history append-only
  between compactions.
- **Don't use Anthropic's server-side context editing** (`clear_tool_uses`) instead of R1. Each clear is a rewrite,
  and kurtkode's own compaction already controls when that happens.
- **Don't switch models mid-session to save money.** The switch rewrites the history; use subagents instead.

## 7. Subscriptions as a backend

This lever is bigger than any of the above: a flat price for what the API would bill at about $1,350 a month here.

**Anthropic: no.** https://code.claude.com/docs/en/legal-and-compliance says third-party developers may not offer
Claude.ai login or route requests through Free, Pro, Max or Ultra credentials; products, the Agent SDK included,
should use API keys. Anthropic blocked tools that did so in January–April 2026 (OpenCode removed its Anthropic login
in March).

As of the 2026-10-07 support update, the Agent SDK and `claude -p` signed in with a plan draw on the plan. An end user
running the unmodified Claude Code binary with their own login is allowed. Whether a third-party app may spawn the
user's own `claude -p` for them is not stated; treat it as a gray area and don't build on it without asking
Anthropic.

The legitimate route: Max, Ultra and Team plans now include monthly API credits usable with an API key from a linked
Console organization (https://support.claude.com/en/articles/17154008). Kurtkode only needs to work well with such a
key, which it already does.

**OpenAI: probably yes.** "Sign in with ChatGPT" (announced 2026-09-29, a preview) lets Go, Plus and Pro users spend
their plan quota in third-party apps; OpenCode is a launch partner. The constraints reported: Responses API only,
`store:false` and `stream:true` required, no `max_output_tokens` or temperature.

*Verified later the same day* from https://developers.openai.com/siwc/token-sharing-open-source and
https://help.openai.com/en/articles/20001542:
- Plan usage is "available to all open-source partners" through self-serve dynamic client registration, with no
  client secret.
- Requests go to the public `/v1/responses`.
- Usage counts toward the plan's "ChatGPT Work and Codex usage". Pro has no five-hour limit.

CACHING_PLAN.md Phase 3 has the details and the build.

## 8. Open questions

- **Anthropic's real serving cost for a cached token.** No source gives a provider's actual cost. The case that
  caching makes heavy agent use cheap to serve rests on three things:
  - the price ratios;
  - KV-offload systems (LMCache, Mooncake, DeepSeek's disk cache, which MLA's small KV makes affordable);
  - Anthropic's statement that the hit rate drives subscription limits.
- **How plan quotas weigh cache reads.** Unpublished; community fits say about 0.1×.
- **Gemini explicit-cache details for generateContent.** TTL, minimum, and whether Batch and caching stack.
- **OpenAI.** How `previous_response_id` and reasoning items affect hits, and how compaction calls are billed.
- **The Haiku 5.5 price row** ($0.10 / $0.01, tiered above 100k) looks odd against Haiku 4.5's $1. It is what
  kurtkode's table has; confirm it.
