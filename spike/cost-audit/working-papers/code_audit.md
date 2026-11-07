# kurtkode cost-optimization: code audit

Date: 2026-10-26. Scope: ~/git/kurtkode/AgentCore (read only; nothing built, run, or modified).
Paths below are relative to `AgentCore/Sources/AgentCore/` unless they start with `App/`, `EvalKit/`,
`KurtkodeCLI/` or `kurtkode-eval/` (the last three are under `AgentCore/Sources/`).
OpenRouter listing fetched 2026-10-26 (462 models): `scratchpad/or/openrouter_models.json` (full path:
/private/tmp/claude-1001/-Users-kurt-git-sugar-kurtagent/31759f81-c617-4d82-b869-6dea14aad382/scratchpad/or/openrouter_models.json).
Data checks were read-only Python over `eval-results/runs/*` and `~/Library/Application Support/kurtkode/sessions`.
There is no user `pool.json`, so the shipped pool (`Models/ModelPool.swift:87-97`) is the one in effect.

How a billed request becomes a cost entry: each LLM request goes through `TurnRunner.run` (`LLM/Turn.swift:128-145`).
The caller then builds a `CostEntry` (`LLM/CostEntry.swift:141-172`), either directly (`CostEntry.make`, the
loop's own turns) or through `CostSink.record` (`LLM/CostEntry.swift:329-336`, every side request). The entry holds
the usage, the list price (`CostBreakdown`: uncached input, cache read, cache write at 5 minutes and at 1 hour,
output with reasoning inside it, searches, per-request fee), `charged` (OpenRouter's streamed `usage.cost`, later
replaced by `/generation` `total_cost`) and `spent = charged ?? listPrice.total` (`CostEntry.swift:455`). Entries are
appended to the session file of the run they belong to. A later record with the same `id` replaces the earlier one,
both on load (`Session/SessionStore.swift:538-541`) and in every in-memory consumer (RunTracker, App, CLI, EvalKit,
subagent log). **I found no double counting by id, by subagent nesting, or by retries.** The defects are about
coverage (what reaches run records), attribution (which run, agent and model a cost is filed under), basis (charge
compared with list price), and stale or transient priors.

---

## (A) Every LLM request site

"RunTotals" means the request is in the run record that `kurtkode cost report`, the Spending window and `cost
whatif` read (`Agent/Spending.swift:175-185` → `SessionStore.runRecords`). "Entries" means it is in the session's
cost entries, which the daily and project limits (`Spending.today`, `Agent/Spending.swift:163-172`), `cost check`,
`cost reconcile` and the session-limit baseline (`CostMeter.spent`) read.

| # | Request site | What triggers it | Recorded? | Purpose label | Run it is filed under (agent) | In RunTotals? | Counts toward the live meter? |
|---|---|---|---|---|---|---|---|
| 1 | `Agent/AgentLoop.swift:650-661` (turn) | every model step | yes | `reply`, or `fallbackReply`; relabeled `retryAttempt` / `nudgedReply` in `flushCosts` (`AgentLoop.swift:442-455`) | current run (main or subagent; agent = `main` or the subagent's name) | yes | yes (`:659`) |
| 2 | `Agent/AgentLoop.swift:700-733` (dropped-call recovery: other provider, then fallback) | a tool call lost by the provider | yes, one entry per attempt | lost attempts → `retryAttempt`, fallback → `fallbackReply` | current run | yes | yes |
| 3 | `Agent/Context.swift:384-391` (summary in the loop) | context over `compactAt` | yes | `summary`, or `summaryAttempt` for an unused first try | current run | yes | yes |
| 4 | Manual `/compact` (`App/Sources/Model/ChatController.swift:810-813`, `KurtkodeCLI/CLISession.swift:329-334`) | user | yes | `summary` | **run = nil** (`main`) | no (no run) | no (between runs; the next run's session baseline includes it) |
| 5 | `Agent/AgentLoop.swift:1462-1466` (`ratingSideLoop`, up to 4 requests) | end of a run that used subagents | yes | `rating` | parent run (`main`) | yes | yes |
| 6 | `Agent/Judging.swift:609-610` (grader), called from `Agent/Subagents.swift:704-715` | `importance: high` subagent run | yes | `grading` | **parent run, agent `main`** (not the graded child; `Subagents.swift:708`) | yes, in the parent's | yes |
| 7 | `Agent/Review.swift:147-148` (A6), called from `Agent/Subagents.swift:726-737` | `importance: high` subagent run that changed files | yes | `review` | **parent run, agent `main`** (`Subagents.swift:733`) | yes, in the parent's | yes |
| 8 | `Agent/Review.swift:147` via escalation review (`App/Sources/Model/ChatController.swift:982-1012`) | after a main run below the frontier, opt-in | yes (`recordCost`) | `review` | the reviewed run's id | **no**: the run record is already written | **no** (`meter: nil`, `ChatController.swift:1001`) |
| 9 | `Agent/Review.swift:147` via `/review` (`ChatController.swift:1108-1110`, `CLISession.swift:631-633`) | user | yes | `review` | the reviewed run, or nil for a whole-session review | **no** | **no** (`meter: nil`) |
| 10 | `Agent/SkillRouter.swift:107-108`, called before the loop (`ChatController.swift:1325-1328`, `CLISession.swift:459-466`) | each new user request on an OpenAI-compatible server (default `auto`) | yes (`recordCost` / `persist`) | `routing` | run id from `SessionRun` (`main`) | **no**: emitted outside `AgentLoop`, so `RunTracker` never sees it | yes (`config.costMeter`) |
| 11 | Subagent runs: child `AgentLoop.run` (`Agent/Subagents.swift:604-640`) | `task` call | yes, in the child session (its cost events are **not** forwarded to the parent's emit, `default: break` at `:632`) | as in rows 1–3 | child run (`parentRun` set; agent = subagent name) | yes, in the child's own record. The parent's `children[]` copies `listPrice`/`spent` only | yes (shared meter) |
| 12 | D3 retry (`Agent/Subagents.swift:754-767`) | hard failure of a pool-routed run | yes, as a second child session with `attemptOf` | as in rows 1–3 | new child run | yes (own record) | yes |
| 13 | Escalation hand-over (`CLISession.swift:580-588`, App "Escalate") | user accepts the card | yes, as an ordinary main run | `reply` (**nothing marks it as escalation**) | the new main run | yes | yes |
| 14 | `Debug/Replay.swift:251-261` | user replay | yes, in the replay record | `replay` | nil (`replay`) | no | no |
| 15 | `KurtkodeCLI/DebugCommands.swift:1016-1023` (`cost calibrate`) | user | yes, in its own session | **`reply`** (it is calibration) | synthetic run UUID with no run record (`calibration`) | no | no |
| 16 | `App/Sources/Views/SettingsView.swift:357` ("chat test") | user | **no** | – | – | no | no |
| 17 | EvalKit: bank runs (`EvalKit/Runner.swift:349`), judges (`EvalKit/RunStore.swift:237`), `--review-sim` (`EvalKit/ReviewSim.swift:100`) | eval | in eval stores only | `reply` / judge / `review` (agent `judge`, `reviewer`) | nil for judges and reviews | eval run records only | eval `--max-cost` |
| 18 | `/models` and `/generation` GETs (`LLM/ChatClient.swift:250-273`), including the end-of-run lookup | price list, reconciliation | not billed | – | – | – | – |
| 19 | HTTP and mid-stream transient retries inside `ChatClient.stream` (`LLM/ChatClient.swift:150-200`) | 408/429/5xx, overloaded before generation | not separate entries. The decoder is reset, so usage from the failed attempt is dropped (normally unbilled) | – | – | – | – |

There is no LLM title generation: a grep for `TurnRunner.run` across App and AgentCore finds only the sites above.

---

## (B) Suspected defects

### B1. HIGH: the default grader for an important task is Opus, not Haiku (and the docs say Haiku)

`Models/ModelPool.swift:222-228`, `:257-263`; `Agent/Subagents.swift:704-715`; wiring at
`App/Sources/Model/ChatController.swift:1259-1266` and `KurtkodeCLI/CLISession.swift:421-427`.

How it happens:
1. A task card with `importance: high` and no `tier` asks for `.standard` (`ModelPool.swift:227`).
2. In the shipped pool that is Haiku (the only `.standard` subagent entry).
3. `SubagentRouting.grader` takes the first `.judge` entry that is not the run's own model. The only judge is Haiku,
   which is the run's model, so it falls back to `available(.reviewer).filter(other).max(tier)`, which is **Opus**
   (`:262`). The code comment at `:253-256` admits this.
4. `grade()` sends up to 16k output tokens on native APIs (`Judging.swift:604`).

COST_ARCHITECTURE.md says "Default grader: Haiku grades `importance: high` subagent runs". In the default path it
does not. Opus 5.5 costs exactly 40× Haiku 5.5 on input and output (4/20 against 0.10/0.50 per million) and 20× on
cache reads. Measured Haiku grader-path judgments cost a mean $0.000476 (cf3a, 140 judgments). The same request on
Opus is about **$0.019 per graded run**, about 14× the Haiku subagent run it grades (≈$0.0013–0.0014). That
contradicts "Judges, grader path: a fraction of a run".

The cost is recorded correctly (`grading`), but filed under the parent run and agent `main` (see B3).

Probe: a unit test
`SubagentRouting.grader(main: <anthropic endpoint>, runEndpointID: <same>, runModel: "claude-haiku-5-5", pool: .shipped, endpoints: [anthropic])?.model == "claude-opus-5-5"`.
Live check: a hosted session with an `importance: high` task. The status line says "Grading … on claude-opus-5-5", and
`cost report --by kind` shows the grading entry's dollars.

### B2. MEDIUM: run-record reports leave out requests made outside `AgentLoop`, so the three money views disagree

Rows 4, 8, 9, 10, 14, 15 and 16 in (A).
- `RunTracker` is fed only by `AgentLoop.run`'s emit (`Agent/AgentLoop.swift:257-279`, `Agent/RunRecord.swift:306-321`).
- Skill routing is emitted straight to the session (`ChatController.swift:1325-1328`, `CLISession.swift:461-466`).
- Post-run and `/review` reviews arrive after the run record is written, with `meter: nil`.
- `/compact`, replays and calibration have no run. The Settings chat test is not recorded at all.

`cost report`, the Spending window (`App/Sources/Views/SpendingView.swift:107`) and `cost whatif` sum run records.
The daily and project limits, `cost check` and the session's status total sum entries. They differ by:
- every routing request (~2k uncached tokens per new request on OpenRouter, where routing is on by default; about
  $0.0002 on OpenRouter Haiku, ~15% of a typical Haiku task);
- every review, `/compact`, replay and calibration;
- late reconciliations. `CostReconciler.run` (`LLM/CostEntry.swift:416-449`) rewrites entries' `charged` at launch,
  but run records keep the `spent` they had when the run ended. The report never changes, while entry-based views
  do.

The two reviews also do not count toward the run or session limit at the time they are made.

Probe: on an OpenRouter session with routing on, run one request, then compare
`kurtkode cost report --since 1d --json` (total `spent`) with `kurtkode cost check --day <today> --tz local --json`.
The difference equals the `routing` entries' sum.

### B3. MEDIUM: `--by model` and `--by kind` misfile costs made on other models

`Agent/Spending.swift:46-52` groups whole runs by `record.setup.model` and by run kind. `RunTotals`
(`Agent/RunRecord.swift:333-347`) sums every entry in the run's scope, whatever model served it. That includes:
- the summarizer (another model),
- fallback replies,
- the parent's ratings,
- **the grader (Opus) and the A6 reviewer (deepseek)**, whose sinks use the *parent's* scope with agent `main`
  (`Subagents.swift:708`, `:733`).

So Opus grading dollars appear under the parent's model (for example "claude-haiku-5-5" or "ling-3.0-flash") and under
kind "main". Token totals also mix tokenizers. `cost whatif` then reprices the grader's and summarizer's tokens at the
target model as well (see E).

Probe: in a session with one graded important task, `kurtkode cost report --by model` shows no Opus row, but the
parent model's `spent` exceeds the sum of its `reply`/`summary` entries by the grading entry.

### B4. MEDIUM: `cost whatif` compares a charge against a list price, among other approximations

`KurtkodeCLI/DebugCommands.swift:252-264`; `Agent/Spending.swift:121-131`.
- `actual = Σ Run.spent`, which is the charge where OpenRouter reported one.
- `would = whatIf(...)` is a list price.

For OpenRouter runs, charge and list differ by provider routing. Measured on cf6 deepseek-v4-flash-0731 (reasoning
off), late window: list $0.000735 against charged $0.000996 a run (1.36×). Early window: list $0.00372 against charged
$0.00217 (see B6). So a whatif on the **same** model does not return 1.00×. The other approximations are in (E).

Probe: `kurtkode cost whatif -m openrouter:inclusionai/ling-3.0-flash --eval eval-results/runs/cf2 --no-sessions` on a
single-model store, or `-m` set to the store's own model. Expected 1.00×; any other ratio is basis drift.

### B5. MEDIUM: unpriced requests count $0 toward every limit

`Agent/CostMeter.swift:41-44` (`guard let c = entry.spent, c > 0`). `LLM/CostEntry.swift:218-231` returns `.unknown`
in these cases:
- a native model missing from `PriceList`. On OpenRouter today (so likely on the native APIs too):
  `gemini-3.7-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`, `claude-opus-4-5`,
  `claude-sonnet-4-5`, `claude-opus-4-1`;
- api.openai.com and Azure (their `/models` has no pricing);
- any remote server whose `/models` lacks the id.

Such sessions never reach the $2 run limit or the daily limit. This is documented in the CostMeter comment, but the
UI states limits as if they always apply.

Probe: a unit test where `CostMeter(runLimit: 0.0001, …)` receives an entry with `listPrice == nil, charged == nil` →
`reached == nil`. Live: a native session on `gemini-3.7-flash` with a $0.0001 run limit runs to completion.

### B6. MEDIUM: list prices are taken from a live OpenRouter listing with no sanity check, and a transient 10× listing is frozen into records and the shipped prior

`LLM/CostEntry.swift:237-281` (`RemotePrices`, re-read every 6 h). Stored rates for `deepseek/deepseek-v4-flash-0731`:

| store, time (UTC) | runs | input / output / cache-read per M | mean list a run | mean charged a run |
|---|---|---|---|---|
| cf3a, 2026-10-25 | – | 0.0422 / 0.1694 / 0.028 | – | – |
| cf6, 10-26 10:43–11:18 | 340 | **0.44 / 1.32 / 0.014** | $0.00372 | $0.00217 |
| cf6, 10-26 16:02–16:19 | 140 | 0.0444 / 0.1333 / 0.0014 | $0.000735 | $0.000996 |
| OpenRouter listing, today | – | 0.0444 / 0.1333 / 0.0014 | – | – |

The early cf6 window is exactly 10× and is not borne out by the charges. Consequences:
- 340 stored run records carry list prices that are 10× too high, so `cost report --eval cf6` overstates deepseek
  about 5× across the store;
- the shipped pool note "deepseek … $0.0018 a run" (`Models/ModelPool.swift:93`) disagrees with
  COST_FLOOR_RESULTS.md ($0.00042) and with today's TypicalTask price (≈$0.00045);
- COST_ARCHITECTURE.md's "provider routing made deepseek 2.4× dearer a run **with no list-price change**" is
  contradicted by the stored list rates. Charges did rise about 2.2× in the early window, but the list price also
  moved by 10×.

Probe: the Python one-off I ran (it groups cf6 deepseek runs by `uncachedInput / uncachedTokens`). As a guard, flag an
entry whose `listPrice/charged` ratio is above 3 or below 1/3, or a rate change of 5× or more between consecutive
`RemotePrices` reads.

### B7. LOW–MEDIUM: switch and escalation estimates use inconsistent rules

The switch cost:
- **Native Anthropic:** `PriceList.switchCost` (`LLM/PriceList.swift:138-143`) prices the whole history as a cache
  write (1.25×, or 2× with the 1-hour cache), which is correct for native Anthropic.
- **Native Gemini:** the history at uncached input, which is correct (implicit cache, no write charge).
- **OpenRouter / OpenAI-compatible:** `price(api: .openai)` returns nil (`:113`). The switch *notice*
  (`:147-158`, used by `ChatController.swift:1169` and `CLISession.swift:159`) then gives no dollar figure. The App's
  menu label falls back to the history at plain input (`ChatController.swift:1214-1215`), ignoring the 1.25× write
  that OpenRouter charges for `anthropic/*`, where kurtkode sets cache breakpoints (`LLM/ChatClient.swift:86-88`;
  OpenRouter lists `input_cache_write` 0.125 for Haiku 5.5).
- **Switching back:** "switching back costs as much again" ignores an old model's cache that is still warm (5 min or
  1 h).

The escalation estimate (`Agent/Escalation.swift:92`, `CLISession.swift:561`) is `TypicalTask + context × input`:
- plain input even for an Anthropic target, which disagrees with `switchCost`'s 1.25×;
- `contextTokens` is taken before the hand-over text, so the diff (up to 30 KB, about 9k tokens,
  `Escalation.swift:103`) is not counted;
- the CLI passes `usage.totalTokens` (prompt + completion of the last reply) as the context.

Probe: compare `switchCostLabel` for `anthropic/claude-haiku-5.5` on OpenRouter with the native Haiku label at the same
`contextUsed`. They differ by exactly 1.25×.

### B8. LOW: a run about to be retried is graded anyway

`Agent/Subagents.swift:654-662` decides `planned` (the retry), but the grader at `:704-715` runs regardless. The A6
review checks `planned == nil` (`:724`); the grader does not. A cheap-tier `importance: high` run that hard-fails is
graded (by Haiku) and then retried and graded again.

Probe: a test with a `retryModel` that returns a rung, plus a grader stub that counts calls. A hard-failing first
attempt gives 2 grader calls.

### B9. LOW: labels

- Grader and A6 review entries say `agent: "main"` (`Subagents.swift:708`, `:733`).
- Calibration is `.reply` (`DebugCommands.swift:1020`).
- There is no `escalation` or `judge` purpose, and the hand-over run is indistinguishable from any other main run
  except by its message prefix (`Escalation.handOverPrefix`). Real-session cascade savings cannot be summed without
  joining `EscalationOffer.run` with the next run's `userMessage`.
- `CostEntry.Purpose` has no case for the escalation review as opposed to the A6 subagent review.

### B10. LOW: price-table specifics

See (C).
- `claude-sonnet-5-5` cache read is 0.20 in the table but 0.10 on OpenRouter (`LLM/PriceList.swift:74`), so it is
  overestimated 2×.
- `gemini-3.8-flash` introductory prices are 0.75/3.75/0.075, but OpenRouter lists 0.825/4.125/0.0825 (+10%)
  (`:85`).
- The Haiku 5.5 long-prompt tier (above 100k tokens: 0.50/2.50/0.05, `:77`) is not visible on OpenRouter. If
  Anthropic charges it, OpenRouter-routed Haiku list prices above 100k are underestimated 5× (the charge corrects it).
  If not, native estimates above 100k are 5× high.
- Two entries of the same length (`gemini-4-argon` introductory and regular) depend on `sorted(by:)` keeping the
  intro entry first (`:118`); the tie-break should be explicit (for example on `until != nil`).
- `TypicalTask`, `whatIf` and the escalation estimate use `price.standard` only (`Models/ModelPool.swift:198`,
  `Agent/Spending.swift:122`), ignoring long tiers.

### B11. LOW (latent): `Spending.evalRuns` ignores `children`

`Agent/Spending.swift:188-207` takes `record.totals`, which covers the run's own requests only. A store whose runs
delegate would undercount. None of the 18,893 stored eval runs has children today.

### B12. LOW: end-of-run reconciliation costs up to about 10 s on every OpenRouter run

`Agent/AgentLoop.swift:262-268` with delays [1, 3, 6]. COST_ARCHITECTURE.md itself says records lag minutes ("one in
three after ten"), so most in-run lookups fail. They also cover only hosts of the main, summarizer and fallback
clients, so a grader or reviewer on another host waits for `cost reconcile` at launch. This costs latency, not money.

### Checked and found sound

- **Reconciliation:** it replaces `charged`, never `listPrice` (`CostEntry.swift:364-382`); the native-count list
  price goes to `reconciled.nativeListPrice`. Streamed and native token counts agree on every reconciled entry on
  this Mac (6 checked).
- **Retries:** each attempt is its own entry. Relabeling in `flushCosts` changes the purpose, not the count, and every
  exit path flushes (`AgentLoop.swift:801`, `:848`). D3 retries are separate child sessions.
- **Subagents:** costs live only in child sessions. `CostMeter.spent(session, runs:)` and `costEntries()` add parent
  and children with no overlap. Forks exclude copied children (`ownSubagentRuns`).
- **Token parsing:**
  - Anthropic: prompt = input + cache_read + cache_creation; thinking is inside output_tokens.
  - Gemini: completion = candidates + thoughts; cached tokens are part of the prompt.
  - OpenRouter: `cached_tokens` and `cache_write_tokens` are part of `prompt_tokens`; `reasoning_tokens` is part of
    completion.
  - `CostBreakdown` charges `fresh = prompt − read − write` at input, and reasoning only once (inside output).
- **Cache multipliers:** Anthropic write 1.25× (5 min) and 2× (1 h); explicit read rates (not a blanket 0.1×: Opus
  5.5 is 0.05×, Fable 5.1 0.025×, which matches OpenRouter); Gemini writes at the input price (none reported);
  OpenRouter rates from the listing, falling back to input when missing.

---

## (C) Shipped prices against OpenRouter today

`PriceList.asOf = 2026-10-14`, `version = 2026-10-15.1`, `staleAfterDays = 60`, so the staleness warning starts on
2026-12-14. The `until` dates switch prices automatically: `gemini-4-argon` goes to 4/20/0.20 on 2026-12-01 (UTC), and
`gemini-3.8-flash` and `gemini-3.6-flash` go to 1.50/7.50/0.15 on 2027-01-01. Prices are $ per million tokens; the
OpenRouter values are `pricing.prompt`, `completion` and `input_cache_read` (×10⁶), and its write column is
`input_cache_write`.

| Shipped id (PriceList) | Shipped in / out / read (write) | OpenRouter id | OpenRouter in / out / read (write) | Context | Verdict |
|---|---|---|---|---|---|
| claude-fable-5-1 | 10 / 50 / 0.25 (12.5) | anthropic/claude-fable-5.1 | 10 / 50 / 0.25 (12.5) | 1,000,000 | match |
| claude-fable-5 | 10 / 50 / 1.00 (12.5) | anthropic/claude-fable-5 | 10 / 50 / 1.00 (12.5) | 1,000,000 | match |
| claude-opus-5-5 | 4 / 20 / 0.20 (5.0) | anthropic/claude-opus-5.5 | 4 / 20 / 0.20 (5.0) | 1,000,000 | match |
| claude-opus-5 | 5 / 25 / 0.50 | anthropic/claude-opus-5 | 5 / 25 / 0.50 (6.25) | 1,000,000 | match |
| claude-opus-4-8 / 4-7 / 4-6 | 5 / 25 / 0.50 | anthropic/claude-opus-4.8 / 4.7 / 4.6 | 5 / 25 / 0.50 | 1,000,000 | match |
| claude-sonnet-5-5 | 2 / 10 / **0.20** (2.5) | anthropic/claude-sonnet-5.5 | 2 / 10 / **0.10** (2.5) | 1,000,000 | **differs: cache read 2× high** |
| claude-sonnet-5 | 2 / 10 / 0.20 | anthropic/claude-sonnet-5 | 2 / 10 / 0.20 | 1,000,000 | match |
| claude-sonnet-4-6 | 3 / 15 / 0.30 | anthropic/claude-sonnet-4.6 | 3 / 15 / 0.30 | 1,000,000 | match |
| claude-haiku-5-5 | 0.10 / 0.50 / 0.01 (0.125); above 100k: 0.50 / 2.50 / 0.05 | anthropic/claude-haiku-5.5 | 0.10 / 0.50 / 0.01 (0.125) | 1,000,000 | standard tier matches; long tier not verifiable |
| claude-haiku-4-5 | 1 / 5 / 0.10 | anthropic/claude-haiku-4.5 | 1 / 5 / 0.10 | 200,000 | match |
| gemini-4-argon (until 2026-11-30) | 2 / 10 / 0.10 | google/gemini-4-argon | 2 / 10 / 0.10 (0.1875) | 1,048,576 | match (intro) |
| gemini-3.8-flash (until 2026-12-31) | 0.75 / 3.75 / 0.075 | google/gemini-3.8-flash | **0.825 / 4.125 / 0.0825** | 1,048,576 | **differs: +10%** |
| gemini-3.6-flash (until 2026-12-31) | 0.75 / 3.75 / 0.075 | google/gemini-3.6-flash | 0.75 / 3.75 / 0.075 | 1,048,576 | match |
| gemini-3.1-pro | 2 / 12 / 0.20; above 200k: 4 / 18 / 0.40 | google/gemini-3.1-pro-preview | 2 / 12 / 0.20 | 1,048,576 | match (standard tier) |
| gemini-3-flash | 0.50 / 3.00 / 0.05 | google/gemini-3-flash-preview | 0.50 / 3.00 / 0.05 | 1,048,576 | match |
| gemini-2.5-flash | 0.30 / 2.50 / 0.03 | google/gemini-2.5-flash | 0.30 / 2.50 / 0.03 | 1,048,576 | match |
| (missing) | – | google/gemini-3.7-flash, gemini-3.5-flash, gemini-3.5-flash-lite, gemini-3.1-flash-lite; anthropic/claude-opus-4.5, sonnet-4.5, opus-4.1 | listed | – | **unpriced natively, so limits don't apply (B5)** |

OpenRouter pool entries and the models the audit asked about (priced live through `RemotePrices`, so no stored table
can go stale; the shipped notes are static text):

| Model | Still listed? | In / out / cache read | Context | Notes |
|---|---|---|---|---|
| inclusionai/ling-3.0-flash | **yes** | 0.021 / 0.063 / 0.0042 | 262,144 | the pool note "$0.00025 a run" checks out (TypicalTask = $0.000258). Successor ling-3.1-flash costs 0.075 / 0.225 / 0.015 (3.6×) |
| deepseek/deepseek-v4-flash-0731 | **yes** | 0.0444 / 0.1333 / 0.0014 | 1,048,576 | the pool note "$0.0018 a run" is stale or transient (B6); TypicalTask today = $0.00045. Newer: deepseek-v4.1-flash-1017 (0.15 / 0.60 / 0.003); `~deepseek/deepseek-v4-flash-latest` (0.0422 / 0.1694 / 0.028) |
| inception/mercury-2.5 | **yes** | 0.04 / 0.15 / 0.004 | 260,000 | successor mercury-3 costs 0.10 / 0.35 / 0.01 |

kurtkode does not use those context lengths on OpenRouter. It caps an OpenAI-compatible model at
`min(listed, defaultContextLength = 32,768)` (`Agent/SessionRun.swift:48`, `KurtkodeCLI/CLISession.swift:189-191`),
and native APIs at `min(listed, 200,000)` (`Endpoints/Endpoint.swift:135`). EvalKit pool subagents use 32,768
(`EvalKit/Runner.swift:402`).

TypicalTask at today's list prices (20k prompt, 13k of it cached, 900 out, 8 requests, `Models/ModelPool.swift:191-201`):
- ling: $0.000258;
- deepseek-0731: $0.00045;
- Haiku 5.5: $0.00128, or about $0.00146 with the native cache-write premium on the 7k uncached tokens, which
  TypicalTask ignores;
- Opus 5.5: $0.0486.

---

## (D) Fixed per-request prompt overhead

What a request always carries before any conversation:
- the system prompt: style template plus intro, mode rules, `skills.md`, `delegation.md`, the environment block and
  the "Tools available" line (`Agent/SystemPrompt.swift:95-143`);
- the instruction files (project AGENTS.md / CLAUDE.md, `~/.kurtkode/AGENTS.md`, `~/.claude/CLAUDE.md`, memory);
- the tool definitions, including the `skill` tool, whose description lists every model-invocable skill
  (`Agent/Skills.swift:99-118`).

Bytes (comments stripped from the templates; tool sizes estimated from source, so ±15%):

| Piece | Bytes | ≈ tokens (bytes / 3.5) |
|---|---|---|
| Style template: lean 807 or detailed 1,546; + intro 465; + mode rules (rendered part, about half of 1,884); + skills.md 560; + delegation (lean ≈300 or detailed ≈1,000); + environment and tools line ≈400 | 3.5–5.0 KB | 1.0–1.4k |
| Skills listing in the `skill` tool (30 built-ins: 7,086 B of descriptions + ≈300 B wrapper and schema) | ≈7.4 KB | ≈2.1k |
| Core tool schemas (read_file, list_dir, glob, grep, bash, bash_output, kill_shell, edit_file, write_file, todo_write) | ≈12–14 KB | ≈3.4–4.0k |
| Hosted-session extras: task (+TaskCard params, agent list) ≈2.5 KB, rate_task ≈1.3 KB, ask_user ≈1.2 KB, remember ≈0.7 KB, apply_patch ≈1.0 KB (profile-dependent), present_plan ≈0.7 KB (Plan mode only) | ≈6.7–7.4 KB | ≈1.9–2.1k |
| **Total, hosted session, all tools on, no instruction files or MCP tools** | **≈30–34 KB** | **≈8.5–9.6k tokens** |

Checked against real first-request `promptTokens` in eval store cf6. Those runs have 11 tools including `skill` and
the 30-skill listing, but no task, rate_task, ask_user, remember or user files. The task text is 60–190 characters:

| Model (tokenizer) | 11 tools + skills | 4 tools, no skills |
|---|---|---|
| Haiku 5.5 via OpenRouter (Claude tokenizer) | 6,666–6,752 | 2,273 |
| ling-3.0-flash | 4,897–4,954 | 1,732 |
| deepseek-v4-flash-0731 | 4,769–4,841 | 1,681 |

The bytes/3.5 estimate for the same subset (≈25 KB) is ≈7.1k, which is near Claude's count. Other vendors' tokenizers
count about 28% fewer. Adding the hosted extras (≈2k), a full hosted session's fixed overhead is about
**≈8.7k tokens on Claude and ≈6.4k on ling or deepseek**, before instruction files and MCP schemas, which are
unbounded.

For scale, a cf6 skills-on run averaged 33k prompt tokens over 4.2 requests on Haiku (≈7.9k per request). The fixed
overhead is therefore about 85% of each bank-task request; most of it is cached after the first request. (Measured
only; I am not proposing to trim the skills listing.)

---

## (E) What `cost whatif` assumes

`Agent/Spending.swift:121-131`, `KurtkodeCLI/DebugCommands.swift:252-264`, `App/Sources/Views/SpendingView.swift:91`.
For each priced run record (`spent != nil`):

`would = (promptTokens − cacheReadTokens) × input + cacheReadTokens × cacheRead + completionTokens × output + perRequest × requests`,

at the target's `price.standard`, compared with `Σ spent` (charge where known). It assumes:
1. **The same token counts.** Run totals are summed across requests (and across tokenizers when a run mixes models),
   so the target is assumed to tokenize like the source. HANDOFF records that bytes/3.3 gave 9.3k for a prompt Claude
   counted as 13.4k and Gemini as 7.2k (±40%); none of that is corrected.
2. **The same number of steps and requests.** A different model taking more or fewer steps is ignored. The disclaimer
   says so.
3. **The same cache hits.** Every source cache read becomes a target cache read at the target's read rate:
   - a source with implicit caching (Gemini, OpenRouter) repriced as Anthropic gets 0.1× reads with **no 1.25× write
     premium** (cache-write tokens are billed as plain input), which understates Anthropic;
   - a target without caching gets `cacheRead = input` only if OpenRouter omits `input_cache_read` (`RemotePrices`).
4. **The same reasoning.** `completionTokens` includes thinking, so repricing a reasoning-on run for a reasoning-off
   configuration (or the reverse) keeps the source's thinking volume.
5. **No long-context tiers.** It uses `price.standard` only, so Haiku 5.5 above 100k and Gemini 3.1 Pro above 200k are
   not applied; per-request sizes are lost in the totals anyway.
6. **Every request in the run moves to the target**, including requests made on other models: summarizer, fallback,
   grader (Opus), reviewer, ratings (B3).
7. **No search fees**; per-request fees are kept.
8. **The comparison basis is mixed:** charge against list (B4).
9. **Runs outside run records are not in the total:** routing, post-run reviews, /compact and replays (B2). In
   `--eval`, degraded and infrastructure runs are excluded (`Spending.swift:195-205`); `children` are ignored (B11).

---

## (F) The delegation threshold

`Agent/AgentLoop.swift:555-576`: once per run, when subagents and `delegationAdvice` are on (both default true,
`Agent/SessionRun.swift:91-93`). It needs:
- `readStreak ≥ 6` **consecutive** broad reads (`read_file`, `grep`, `glob`, `list_dir`, `AgentLoop.swift:1554`). Any
  other call (bash, edit, todo_write, task) resets the streak and its bytes.
- `tokens × 5 ≥ budget.limit`, where `tokens = Σ output bytes / estimator.bytesPerToken`. That is 3.3 to start, then
  calibrated to the server's reported prompt sizes and clamped to 1.5–6 (`Agent/Context.swift:104-116`, called at
  `AgentLoop.swift:814`).

Each read's output is capped at `toolOutputBytes = min(200,000, max(16,000, 0.08 × limit × 3.3))`
(`AgentLoop.swift:131-134`).

| Context `limit` | Cap per read | Tokens needed in six reads | Bytes needed (at 3.3 B/tok; Claude ≈2.3 B/tok) | Average per read |
|---|---|---|---|---|
| 200,000 (native Claude or Gemini: `min(listed, 200k)`) | 52,800 B | 40,000 | 132,000 B (≈92,000 B) | **≈22 KB (≈15 KB)**, i.e. six ≈330-line files read whole, back to back |
| 1,000,000 (if the cap were lifted) | 200,000 B | 200,000 | 660,000 B | ≈110 KB |
| 32,768 (OpenRouter default: `min(listed, 32,768)`) | 16,000 B | 6,554 | 21,600 B | ≈3.6 KB, which trips easily |

Why it never tripped for a Haiku parent on the native 200k context:
- bank fixtures are a few KB per file;
- frugal parents interleave reads with other calls (todo_write, bash), which reset the streak;
- the average read must be about 4–6× a typical source file for six reads in a row.

The same Haiku via OpenRouter gets a 32k budget, where the threshold is about 6× easier to reach. The trigger depends
on which endpoint serves the model, not on the model.

---

## (G) EvalKit simulation methodology

**`--retry-sim`** (`kurtkode-eval/main.swift:294-316`):
- Over stored runs with `degradation == nil && infra == nil`, it restores each fixture, resolves citations, and asks
  whether `checks.retryableFailures` is non-empty.
- It reports counts only (fires, fires on gold failures). It does not estimate whether the next rung would succeed or
  what the retry costs; the next rung's stored run would supply that.
- **Excluding infrastructure failures removes the hard failures most likely to fire D3 in production** (provider
  errors, cut streams), so the live firing rate and its cost are understated.

**`--trigger-sim`** (`EvalKit/TriggerSim.swift`; driver `main.swift:318-342`). It excludes degraded and infrastructure
runs.
- **Run cost** (`:39`) is `totals.charged ?? totals.spent ?? listPrice`: the charge for OpenRouter, list price for
  native APIs, so the basis is mixed.
- **Judge cost** (`:56`) is the judge's `listPrice`, summed over all its requests. It **includes the judge's own
  prompt tokens**. For the parent path, though, the judge context is a freshly built short parent
  (`EvalKit/RunStore.swift:247-262`). A real session's rating resends the whole parent history (`ratingSideLoop`,
  mostly cached), so session cost per rating grows with session length.
- **Review cost** (`:60`) is `charged ?? listPrice`.
- **Precision and recall** (`table`, `:115-133`) are computed over "runs it applies to" (runs with that judge's or
  reviewer's verdict), with **no base-rate correction**:
  - Judges: today's stores are not enriched (bank1 judged 14 of 42 real failures and 190 of 570 real passes, both
    6.9%; cf3a mercury-2.5 judged all 140). But `RunStore.sample` (`EvalKit/RunStore.swift:390-399`, `--sample N`)
    puts every real failure first and would enrich any future judged sample.
  - Reviews: they come from the review-sim sample (`EvalKit/ReviewSim.swift:39-47`): every code-touching real failure
    plus 2 × perGroup passes. In bank1-rows that is 8 real failures and 24 passes per reviewer, a **25% failure share
    against about 7% in the store**. Haiku's sample precision of 8/10 = 80% becomes **≈47%** at a 6.9% base rate:
    1.0 × 0.069 / (0.069 + 0.083 × 0.931). Deepseek's 0/24 false alarms hide the same issue.
- **Ladder replay** (`:152-182`) has three biases:
  - **Unjudged or unreviewed runs cost $0 and never fire** (`judgeCosts[j] ?? 0`, `judges[j] ?? 3`, `reviews[r] ??
    "looks_right"`; `:96`, `:100-101`, `:104`, `:107`). Where judging or review covered a sample (review-sim: 32 of 612
    real bank1 runs), cascade cost is understated, and recall reflects only the reviewed failures.
  - **An escalated step costs the next model's fresh stored run.** It ignores the hand-over (re-reading the
    conversation and diff at the new model, cache writes) and assumes the stronger model starts from a clean fixture,
    not from the cheap model's partial or bad edits.
  - **Costs mix charge and list** (above).

**`--review-sim`** (`main.swift:344-390`, `ReviewSim.swift`):
- Sample: every code-touching real failure, up to `perGroup` of each of four degradations, and `2 × perGroup` passing
  code runs. It excludes infrastructure runs and **includes degraded copies**.
- The report gives per-group catch rates and the false-alarm rate on passes, which is fine, plus an "all failures" row
  that pools synthetic and real failures.
- The quoted "caught 51 of 55 / 56 of 56 bad changes" is mostly synthetic: 48 of 56 per reviewer are degradations.
  On the 8 **real** failures (bank1-rows.jsonl):

  | Reviewer | Real failures caught | False alarms on 24 passes |
  |---|---|---|
  | deepseek-off | 6 of 8 | 0 |
  | gemini-3.8-flash | 6 of 8 | 0 |
  | qwen3-coder-30b | 5 of 8 | 0 |
  | Haiku 5.5 | 8 of 8 | 2 |

- The review's cost includes the reviewer's prompt (about 1.0–1.4k tokens a review). Deepseek-off was charged
  $0.000118 against a $0.000064 list a review (1.8×).
- `--max-cost` is checked before each review, but up to `--parallel-remote` reviews can be in flight past the cap.

**Judge calibration** (`EvalKit/RunStore.swift:225-310`): the judge's cost is the list price of all its requests,
including prompts. Precision there is computed on stores that include degraded copies (bank1 and cf5 judged all 459
and 113 degraded/infrastructure runs) when the `--degrade` table reports catch rates. Those are recall-style numbers;
any precision quoted from a degraded-inclusive sample needs the same base-rate correction.
