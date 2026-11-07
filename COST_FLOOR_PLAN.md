# Cost-floor testing: the cheapest model that clears the bar

Proposed 2026-10-25; decisions taken the same day (see "Decisions"). **Run the same day; results and what changed
from this plan are in COST_FLOOR_RESULTS.md** ($83.22 spent of $185). Builds on EVAL_PLAN.md and EVAL_RESULTS.md (the
run store, the bank, the judges) and on SUBAGENT_ROUTING_DESIGN.md (the router). **Budget: $185 over about 24
hours**, the user's ($100, plus $25 for reference trials, $40 to screen every model, $20 for more delegation
parents).

## The goal, stated as a decision

For a task, **use the cheapest model configuration whose chance of success clears a quality floor**. This plan
produces three things, so that decision can be made and checked:

1. **A cost–quality frontier** per task kind and difficulty: success rate (with an interval) against cost per run,
   and **cost per success** (cost per run ÷ success rate), the number to minimize.
2. **A "cheapest above the floor" table**: for floors of 80%, 90% and 95%, the cheapest configuration whose
   interval's lower bound clears the floor, per task kind where the data allows and overall where it doesn't.
3. **The router's first real data**: every run goes into the run store, ready for P3's outcome index.

The same goal applies to two things beyond subagents:
- **Judges**: the cheapest judge that is accurate enough.
- **Delegation**: does an expensive parent with cheap subagents beat the expensive model doing it all, at the same
  quality?

## The field

| | Count |
|---|---|
| OpenRouter models with tool calling and a 32k+ context, real ids (no `~` aliases, no `openrouter/` routers) | 371 |
| ... of which free (`:free`, rate-limited) | 16 |
| ... paid, with a typical bank run ≤ $0.01 | 176 |
| ... ≤ $0.02 | 222 |
| ... ≤ $0.05 | 297 |
| ... over $0.05 (frontier and "pro" models, up to $0.70 a run) | 58 |

A "typical run" here is 16k input and 1.2k output tokens at list price, the bank's mean so far. Thinking models
write more, so their real cost will be higher; screening measures it.

**Variants are deduplicated.** A model and its `:batch`, `:nitro`, `:floor` and dated versions count as one, the
newest, and `:thinking` counts as its own configuration. A configuration is a model, its reasoning setting, and
the provider when one is pinned. This probably leaves **150–200 distinct candidates**; the exact number comes out of
stage 0.

## The stages: cheap first, successive halving

Each stage spends money only on candidates that could still win. A model that can't clear the floor on easy tasks
can't be the cheapest one above it on hard ones.

| Stage | What | Candidates | Budget |
|---|---|---|---|
| **0. Catalog** | Fetch, filter, dedupe. Thinking models get two configurations, reasoning off and at its default (D6). Providers that train on prompts are excluded (D4), and models left with none are noted as unavailable | ~355 paid → ~200 models, ~280 configurations | $0 |
| **1. Smoke screen** | 6 tasks (search, explain, fix, edit, write-tests, review), 1 trial, **cheapest first**. A configuration over $0.05 a run runs 3 of the 6 first and stops at the first two failures. Drops anything that can't run the agent loop or passes fewer than 5 of 6 | every paid model (D5) | **$48** |
| **2. Bank** | The 34-task bank, 1 trial. Keeps the Pareto set on cost per success, plus any configuration whose interval overlaps it | ~60 survivors | **$20** |
| **3a. Hard tier, finalists** | 12–15 new, harder tasks, 3 trials, plus 2 more bank trials | ~15 finalists | **$25** |
| **3b. Hard tier, references** | About 5 frontier models (Claude Opus and Sonnet, a GPT-5.x, a Gemini Pro, one more), 3 trials, hard tier only (D3) | 5 | **$35** |
| **4. Delegation economics** | Parents: gemini-4-argon, a Claude model, a GPT-5.x, and the cheapest model that clears 95% (D7). Each alone, and with cheap subagents from stage 3 (forced delegation), plus the cheap model alone; on the five delegation scenarios and 4 hard tasks; 3 trials | 4 parents | **$35** |
| **5. Cheapest judge** | Re-judge stored bank1 runs (with gold) by the parent path with ~10 cheap OpenRouter judges; compare with argon's kappa 0.71 | ~10 judges | **$7** |
| **Reserve** | Retries, providers that fail, a stage that runs over | | **$15** |

**Stopping rules**:
- Each stage has a hard cap at its budget. Stage 1 goes cheapest first, so a cap reached leaves out only the
  priciest models, and the results list them.
- Spending is read from OpenRouter's own account of the key (`/key` usage), not only from the replies.
- A stage that hits its cap stops starting runs and reports what it has.
- Nothing past the total of $185 runs. Google (argon) spending counts in the same total.

**Order**: 0 → 1 → 2, then 3 and 5 at the same time, then 4, which needs stage 3's frontier. The local and bang
models join stages 1–3 for free, as time allows.

## Engineering before spending (hours 0–4)

1. **Spending guard across processes**: one budget file, the `/key` usage polled each minute, a cap per stage and in
   all; runs start only under it. The charges come from OpenRouter's per-reply cost and its generation records (the
   reconciler that already exists).
2. **Catalog import**: candidates from the public `/models` list, deduplicated, with each model's price and
   tool support. History shapes come from the existing family table; an unknown family gets the default shape and is
   noted.
3. **Infrastructure failures classified as they happen**: an HTTP error, an unsupported tool format, or a provider
   that drops calls is recorded as `infra` and retried once on another provider (`provider.ignore`), not counted as a
   model failure. Last time, 168 runs had to be removed by hand for this reason.
4. **The hard tier**: 12–15 tasks, with the same gold discipline (right, idle, wrong and stray-edit outcomes tested
   before any model runs). Kinds:
   - a change across 3–5 files
   - a bug that needs reading two modules to find
   - a refactor with a trap (a name used in a string)
   - an investigation across 10+ files with a short answer
   - tests for edge cases
   - a review with a subtle bug
   - a task whose obvious fix is wrong
5. **Forced delegation**: a parent setting that requires a `task` call for the broad parts, and a "split by
   kurtkode" variant. Last time no model delegated on its own, so delegation must be made to happen to be measured.
6. **Report additions**:
   - cost per success, by model and kind
   - the frontier plot (inline SVG in Markdown, or a CSV to plot)
   - the "cheapest above the floor" table, which uses the Wilson lower bound
   - provider variation where the same model ran on several providers

## Statistics, honestly

- **Floors can be certified overall, not per kind.** The bank alone gives ~4 tasks per kind × 3 trials = 12 runs, and
  12 of 12 has a lower bound of 76%, so no single kind can be shown to clear 90% with this budget. Overall (34 + 15
  tasks × 3 trials, about 150 runs per finalist), 150 of 150 has a lower bound of 97.5%, which can certify 90% and
  95% floors. **Per-kind numbers are reported as estimates with their intervals, and the floor table uses overall
  rates.**
- **Rankings use cost per success**, with its interval derived from the pass-rate interval.
- **A 95% floor is strict** (D1): a finalist with ~150 runs may fail at most about 3 of them to keep a lower bound
  near 95%. The table also shows 80% and 90%.
- **The stage-1 and stage-2 cuts are deliberately generous** (keep anything whose interval overlaps the frontier),
  so a model isn't dropped on a single unlucky run.

## What the user gets after 24 hours

- **COST_FLOOR_RESULTS.md**:
  - the frontier
  - the cheapest models above 80/90/95%, with their cost per success
  - which cheap models aren't reliable (tool-call failures, provider variance)
  - whether cheap subagents under a strong parent save money at the same quality
  - the cheapest adequate judge
- **The run store** with every run, for the router (P3).
- **A recommended default setup**: parent model, subagent model and judge model, with the expected cost per task at
  each floor.

## Decisions (2026-10-25, the user)

1. **Floor: 95%.** Optimize for it; also report 80% and 90%.
2. **Free models: no.** The 16 `:free` models are left out.
3. **References: about 5 frontier models, 3 trials each**, on the hard tier. That adds $25 to the budget.
4. **Providers: only those that don't train on prompts** (OpenRouter's `data_collection: deny`).
5. **Screening: every paid model**, cheapest first. That adds $40.
6. **Thinking models: two configurations**, reasoning off and at its default.
7. **Delegation parents: all four**: gemini-4-argon, a Claude model, a GPT-5.x, and the cheapest model that clears
   95%. That adds $20.

**Keys**: OpenRouter's (and Google's, for argon) from the Keychain. The eval binary is built once before the paid
runs, so expect one Keychain prompt per key.
