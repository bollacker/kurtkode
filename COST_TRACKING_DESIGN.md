# Cost tracking: design

Written 2026-10-15, revised the same day after the user set the purpose. **Purpose**: choose models, for the main
agent and for each kind of subagent task, by picking the cheapest that does a good enough job. Later work judges how
well each agent run did; this stage captures **accurate, complete, attributable cost data** for every agent run, so
cost can be put next to quality. Spending limits and spending dashboards are out of scope (the existing limits stay as
they are); so are sessions recorded before this work.

## What "accurate" means here

1. **Complete**: every request that could be billed is counted, including the ones that produce no message today:
   summaries (compaction, `/compact`, a summarizer model), a summary's cached attempt that fell back, attempts billed
   and then retried elsewhere, cut, cancelled and timed-out replies, fallback-model replies, empty replies that were
   asked again.
2. **Comparable**: the number used to compare models is the **list price** of the exact tokens the server reported,
   priced at the provider's published rates for that day. What the account was actually charged (free tier, credits,
   discounts, OpenRouter's choice of provider) is recorded beside it but isn't what models are compared on.
3. **Exactly priced**: every billing component priced at its own rate: uncached input, cache reads, cache writes (5 min
   and 1 h), output, reasoning (billed as output), searches; long-prompt tiers; the price that held on the day.
4. **Attributable**: each request belongs to exactly one agent run (the main agent's run for a user message, or one
   subagent run), so a run's cost is a sum of its own entries, nothing shared and nothing counted twice.
5. **Explained and checkable**: each entry keeps the server's raw usage, the rates used, and the server's request id,
   so any number can be recomputed and matched against the provider's own records.

## Today, against those

- Replies keep `Usage` (tokens, one `cost`); subagent replies are in their child sessions; usage counts as it arrives,
  so a cut reply keeps its input (6073507).
- **Missing**: summaries and their fallbacks; billed-then-retried attempts (a lost reply retried elsewhere keeps only the
  winner); nudged empty replies (removed from the history, kept only in the wire log); Gemini search grounding (no
  price); the split by component (only a total); the rates used and price-list date; request ids; the raw usage object.
- **Not comparable**: OpenRouter's `cost` is what it charged through the provider it chose; Claude and Gemini costs are
  list-price estimates already. Local models get nothing (no dollars; their time and tokens are in meta).
- **Thin attribution**: a run isn't a recorded unit; the agent definition, model settings (temperature, effort, thinking
  budget, max tokens), prompt style and kurtkode build that produced a run aren't recorded with it.

## The units

- **Cost entry**: one billed request. Written into the session file of the agent run it belongs to (main session or
  subagent child session) as a `cost` record, appended when the request ends; older builds skip unknown records.
- **Agent run**: what gets judged later.
  - A **main run**: one user message and everything the main agent did for it, in the main session.
  - A **subagent run**: one `task` call, which is already a child session (`SessionHeader.parent`, `agent`).
  - Each run gets a **run record** at its end (`run` record, same files) with its totals and the facts needed to
    judge and compare it (below). A main run's totals cover its own entries only; its subagent runs are listed by id
    with their totals, so "this task, all in" is a sum and "this agent's own cost" stays separate.
  - A **session's** cost is the sum of its main runs (and, through them, their subagent runs), plus the few entries
    that belong to no run: a `/compact` typed between runs, replays. Those carry `run: nil` and a purpose, so the sum
    is exact and they never land in an agent's cost.
  - **Delegation is charged to the parent**: writing a `task` call is the parent's output and reading the report back
    is the parent's input, so both are in the parent's entries already; a subagent run's cost is only its own
    requests. The sizes of the task and the report are recorded on the subagent's run record for analysis.

## Cost entry

| Field | Meaning |
|---|---|
| `id`, `start`, `end` | entry id; request start and end |
| `run`, `agent` | the agent run (main run id or subagent run id), the agent kind (`main`, `explore`, `general`, a custom agent's name) |
| `purpose` | `reply`, `retryAttempt` (billed, then retried elsewhere), `fallbackReply`, `nudgedReply` (empty, asked again), `summary`, `summaryAttempt` (the cached try that fell back), `replay` (eval runs use the ordinary purposes; their entries are in the eval results) |
| `endpoint`, `api`, `provider`, `requestedModel`, `servedModel` | where it went; who served it (OpenRouter's provider; Claude's server-side fallback model) |
| `requestID` | the server's id: Anthropic `request-id` header and message id, OpenRouter generation id, Gemini `responseId` |
| `wireRecord`, `message` | links to the wire log record and the message, when there are |
| `ended` | `completed`, `cut`, `cancelled`, `timedOut`, `failed`, plus `billing: certain/uncertain` (a stream that failed after the server started it may or may not be billed; reconciliation settles it) |
| `usageRaw` | the server's usage object verbatim (Anthropic `usage`, Gemini `usageMetadata`, OpenAI/OpenRouter `usage`) |
| `tokens` | uncached input, cache read, cache write 5 min, cache write 1 h, output, of which reasoning, searches |
| `listPrice` | per component and total, in dollars; `rates` (per million, per search, the tier applied) and `priceListDate` |
| `charged` | what the account was charged when known: OpenRouter's reported cost (then its generation record), `0` on a free tier, absent when unknown. Never used to compare models |
| `time` | time to first token, total, output tokens per second (also for local models) |
| `promptMix` | the input's tokens by cause, estimated by the loop: system prompt, tool definitions, history before this run, this run's tool outputs, subagent reports, new user text |

## Run record

| Field | Meaning |
|---|---|
| `run`, `parentRun`, `taskCall` | ids; a subagent run's parent run and the `task` call that started it |
| `agent` | name, and a hash of its definition (instructions, tool list), so an edited agent is a different agent |
| `model setup` | endpoint, model, temperature, effort/thinking budget, max output, prompt style (lean/detailed), profile name |
| `build` | kurtkode version and git commit |
| `task` | the prompt (a subagent's task text; the main run's user message), its size, and a hash for grouping repeats |
| `totals` | entries, list-price dollars by component and in all, charged dollars, tokens, wall time, model time |
| `outcome` | how it ended (stop reason), steps, tool calls by name, errors, denied calls, files changed, compactions, the report's size (subagent) or the final reply's |
| `delegation` | for a subagent run: the size (characters and estimated tokens) of the `task` call the parent wrote and of the report it read back. Their cost is the parent's (in its entries); the sizes are for analysis |
| `children` | subagent runs started, with their totals |
| `judgment` | empty now; filled later by whatever judges the run (a person, a grader model, tests) |

## Pricing accuracy

- `PriceList` gains: per-component rates returned with the cost (not just a total); Gemini search grounding per query;
  explicit cache-write rates per provider (no multiplier constants in code); request options that change a price
  (batch, priority, data residency: none used today, recorded so a future one isn't silently mispriced); a version
  string per edit. A model without a price gets `listPrice: unknown`, never zero, and the run record says how many
  of its entries were unpriced.
- **OpenRouter**: list price for comparison comes from the model's published per-token price (the `/models` list,
  already read for prices) times the reported tokens; the charge is the reported `cost`. A follow-up fetch of the
  generation record (`/generation?id=`, one GET per reply, on by default) gives the exact charge and the native token
  counts afterwards; the entry is updated by a second `cost` record with the same id (`reconciled: true`).
- **Local models** (LM Studio): no dollars, and no hourly rate; tokens, time, tokens per second, the machine (model,
  chip, memory) and the model's quantization and context are recorded.
- **Tests**: each provider's usage shapes priced against hand arithmetic (cache writes at both durations, long-prompt
  tiers, thinking, searches, a fallback model mid-reply, a cut stream); every purpose above produces exactly one entry
  per request (MockServer: a compaction with a fallback, a lost reply retried elsewhere, a nudged empty reply, a
  replay).

## Checking against the providers

- Request ids make every entry findable in the provider's records.
- **OpenRouter**: per-request reconciliation through the generation record (above).
- **Anthropic and Gemini**: their usage is reported per day, not per request, to ordinary keys. A dedicated API key (a
  separate Anthropic workspace; a separate Google Cloud project) for kurtkode experiments makes the console's daily
  totals comparable to `kurtkode cost check --day 2026-10-20 --endpoint Anthropic`, which sums the entries for that key
  and day by model. Anthropic's Admin API (cost and usage reports) could automate it, but it needs an admin key.
- A small **calibration run** after any pricing change: a fixed set of requests on each paid model (a few cents), their
  entries summed and compared with the console the next day; the result is written down in PLAN.md.

## Getting the data out

`kurtkode runs [--since DATE] [--agent NAME] [--json|--csv]`: one row per agent run (the run record flattened, plus
its entries' totals), the table later analysis joins with judgments. `kurtkode inspect` shows a run's entries.
Views in the app (an inspector Costs tab, a spending window) wait until the data is right.

## Phases

1. **Entries**: the `cost` record for every purpose (the main loop, subagents, `Compactor`, retries, fallbacks,
   nudges, replays, evals), request ids, raw usage, `PriceList` per-component rates with versions and Gemini
   grounding, `charged` vs `listPrice`, local timing. Tests as above; checked on a local Gemma run (unpriced but timed)
   and on recorded Claude/Gemini sessions replayed only through the decoders (no new spending).
2. **Runs**: the run record (agent definition hash, model setup, build, task, outcome, delegation, children),
   `promptMix`, `kurtkode runs` export.
3. **Checks**: OpenRouter generation reconciliation, `kurtkode cost check`, a first calibration run on each paid model
   (with the user's go-ahead and a cap).

## Decisions (2026-10-15, the user)

1. **Models are compared on list price** of the reported tokens; the actual charge is recorded beside it only.
2. **Local models**: time, tokens and hardware only; no hourly rate.
3. **Delegation is the parent's cost**: writing the task and reading the report are charged to the parent (they're its
   own requests); the sizes are recorded on the subagent's run record for analysis.
4. **Dedicated API keys** per provider for kurtkode experiments are acceptable (the user creates and enters them); the
   **OpenRouter per-request check** is on by default.
5. **Both units**: the main run (one user message) and the session; the session is the sum of its runs plus the
   entries outside any run (manual `/compact`, replays).

## Status

- **Phase 1 built** (2026-10-15): `LLM/CostEntry.swift` (`CostEntry`, `CostBreakdown`, `PriceLookup`, `RemotePrices`,
  `CostScope`, `CostSink`), `PriceList` with explicit rates per component and a `version`, request ids and raw usage
  from all three decoders (`StreamEvent.requestID`, `.usageRaw`; `TurnMeta.requestIDs`, `.usageRaw`), Gemini search
  counts (`webSearches`, unpriced), `AgentEvent.cost` and `SessionRecord.cost` (`Session.costs`), entries from every
  loop request (purpose settled after the nudge and retry decisions), summaries (`Compactor.summarize`, `/compact`
  in the app and the CLI), subagent runs (their child sessions), replays (in the replay record, beside the wire log,
  since replays need the wire log anyway), evals (`TrialResult.listPrice`, `unpricedRequests`, `costEntries`), and
  `--output stream-json` (`cost` events). Not recorded: Settings' connection test (one tiny request, not session work).
- **Checks**: 11 tests (pricing by component, long tier, OpenRouter list parsing, ids and raw usage, nudged and
  retried replies, summary attempts, a cut stream, subagent entries in the child session, the session-file round trip).
  86 recorded Claude and Gemini responses from sessions 8 and 9 decoded again: all yield ids and raw usage; the 81
  whose sessions recorded a cost match it to 1e-9; the other 5 are summaries, which were never recorded before. Live on
  Gemma: a CLI run with an explore subagent (3 entries in the main session, 3 in the child, timed, "not priced"); the
  app at a 9k context: 20 reply entries for 20 replies, 7 summary entries for 7 compactions, one run.
- **Phase 2 built** (2026-10-16): `Agent/RunRecord.swift` (`AgentRunRecord`: setup, build, machine and local model,
  task, totals by component, outcome, children; `BuildInfo` = version, executable hash, git commit and dirty flag when
  the executable is in a checkout; `MachineInfo` from sysctl; `LocalModelInfo` from LM Studio's `/api/v0/models`),
  `AgentLoop.run` passing every event through a `RunTracker` and sending `.runEnded` just before `.finished`,
  `SessionRecord.run` (`Session.runs`) from the app, the CLI, subagent child sessions and eval results, `SubagentEnd`
  with the run's list price, request counts and the delegation sizes (task written, report read back as returned),
  `promptMix` on every loop reply's entry, `SessionStore.runRecords()`, and `kurtkode runs [--since] [--agent]
  [--json|--csv] [-o]`. **Each send is its own run** (`CostScope.run` is new per send; `userMessage` groups a /retry
  or a Continue with the first run), refining phase 1, where the run id was the user message.
- **Checks**: 3 more tests (a main run and its subagent's records linked by `parentRun`, totals, outcome, task,
  delegation sizes, definition hashes; `promptMix` adding up to the reported prompt; the CSV's columns). Live on
  Gemma: a CLI run with an explore subagent (`kurtkode runs` table and CSV: delegation 283 / 794 bytes, wall 152 s vs
  model 20 s for the main run, build commit and dirty flag, M1 Max 64 GB, 4-bit, 64k context) and an app run.
- **Phase 3 built** (2026-10-16), except the calibration run itself: **OpenRouter reconciliation**: at the end of
  each run (and for each replay), every reply with a `gen-` id is looked up at `/generation?id=` (tries after 0, 1, 3,
  6 s; `AgentConfig.generationLookupDelays`) and recorded again under the same id with `reconciled` (the exact
  charge, native token counts, provider, the raw record, and the list price of the native counts); `charged` becomes
  the provider's figure; a later record of an entry replaces the earlier one everywhere (session load, app, CLI, run
  tracker, evals); `RunTotals.reconciledRequests`. **`kurtkode cost check --day D [--tz] [--endpoint] [--json]`**:
  a day's entries (sessions, subagent runs, replays) by endpoint and model, tokens by kind, list price, charged,
  with counts of unpriced, early-ended and reconciled requests. **`kurtkode cost calibrate -m ENDPOINT:MODEL
  [--yes]`**: three fixed requests (a short one; a ~9k-token prompt twice, the second reading the cache) recorded in a
  session of their own; without `--yes` it only shows the plan and the estimated list price (no key read, nothing
  sent). Estimates at today's list prices: Haiku 5.5 ≈ $0.002, Opus 5.5 ≈ $0.06, Gemini 3 Flash ≈ $0.007,
  OpenRouter's Claude Haiku 4.5 ≈ $0.013.
- **Checks**: 4 more tests (a reconciled OpenRouter reply with its native list price and the run's totals; a later
  record replacing an earlier one in the session; `cost check` sums and time zones; `calibrate` without `--yes`).
  Live: `cost check` on a day of local requests; `calibrate` dry runs on the user's Anthropic, Gemini and OpenRouter
  endpoints.
- **Calibration run** (2026-10-16, about 12:00 UTC, the user's existing keys, a $0.15 cap): spent $0.0995 at list
  price. `kurtkode cost check --day 2026-10-16` to compare with each console:

  | Endpoint | Model | Reqs | Uncached in | Cache read | Cache write | Output (thinking) | List price | Charged |
  |---|---|---|---|---|---|---|---|---|
  | Anthropic | claude-haiku-5-5 | 3 | 47 | 13,397 | 13,397 | 159 (149) | $0.001893 | – |
  | Anthropic | claude-opus-5-5 | 3 | 47 | 13,397 | 13,397 | 109 (99) | $0.072032 | – |
  | Google Gemini | gemini-3-flash-preview | 3 | 10,383 | 4,080 | 0 | 388 (381) | $0.006559 | – |
  | Openrouter | anthropic/claude-haiku-4.5 | 3 | 18,970 | 0 | 0 | 14 | $0.019040 | $0.019040 |

  Findings: (1) **OpenRouter's generation records lag by minutes**, not seconds: the end-of-run lookup (up to ~10 s)
  found none; ten minutes later one of three was there (its native counts equal the streamed ones; charge = list price;
  served by Amazon Bedrock). `kurtkode cost reconcile [--since Nd]` (new) checks the rest later and says why when it
  can't. (2) **OpenRouter didn't cache the repeated Claude prompt** (kurtkode sends no `cache_control` on OpenAI-format
  requests): a cost issue for Claude via OpenRouter, not an accuracy one. (3) The token estimate (bytes / 3.3) was 9.3k
  for a prompt Claude counts as 13.4k and Gemini as 7.2k: estimates aren't used for costs (the servers' counts are),
  but `calibrate`'s estimate was low. `calibrate --max-output N` (new) bounds a run's worst case.
- **Follow-ups built** (2026-10-16): `CostReconciler` (in AgentCore) checks pending OpenRouter records at least a
  minute old from the last 30 days, at most 50 a time: in the background at app launch (after 20 s) and at the
  interactive CLI's start, and on demand with `kurtkode cost reconcile`. All three calibration records were found
  that way (charged = list price for each). **Claude through OpenRouter now marks cache breakpoints**
  (`cache_control` on the system prompt's and the last user or tool message's text parts; `ttl: 1h` with the hour
  setting), so repeats are billed as cache reads; other models and servers send plain text as before. 2 more tests
  (343). Seen live (OpenRouter calibration again, $0.0129): the long prompt wrote 9,470 tokens to the cache
  ($0.011866) and the repeat read them ($0.000975, was $0.009498 uncached); charges match list price to the cent's
  ten-thousandth. Calibration spending in all: $0.1124 of the $0.15 cap.
- **Next**: compare the table with the Anthropic and Google consoles (same keys, same day; nothing else used them
  between the runs).
- **Displays read the cost records** (2026-10-16): one definition, `CostEntry.spent` (the charge where the server
  said it, else list price; nil unpriced), summed by `CostSummary`. The toolbar total (with a tooltip by purpose, list
  price by component, charged, unpriced), the spending limits (`CostMeter.spent`), the Debug window (each turn's cost,
  the details: list price by component, rates and price list, the provider's record, billing, request ids; the stats
  strip's total with summaries and by provider: OpenRouter's provider, else "Anthropic" / "Google", else the host),
  the Journal's caption (summaries included in the session's figure), the Agents tab (each run's cost), the CLI (a
  line after each priced run: spent, requests, summaries, subagents; `-p --output json` `cost_usd` with
  `list_price_usd` and `cost_is_estimate`; `inspect`: the session's cost line, a cost column, and each turn's detail).
  Summaries, retried attempts and nudged replies now count everywhere; sessions recorded before phase 1 show no cost.
  2 more tests (345).
