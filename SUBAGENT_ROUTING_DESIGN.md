# Subagent routing: design

Written 2026-10-24. Status: **decisions D1–D8 taken the same day (see "Decisions"); P1 (judging) built and committed the same day
(see "P1 as built"); P2 (delegation rules, task bank, judge calibration) built and committed the same day
(see "P2 as built")**. This design builds on `SUBAGENTS_DESIGN.md` (each subagent run
is a child session), `COST_TRACKING_DESIGN.md` (a cost entry for every request, a run record for every run, and an
empty `judgment` field on the run record) and `SYSTEM_PROMPT.md` (prompt templates).

## The goal

Subagents should be used, placed and judged on purpose rather than by chance. The design covers six things:

1. **When** to hand a task to a subagent at all.
2. **Which model** runs it.
3. **How well it did**, as judged by the parent agent (and by tests and the user, where they can).
4. **Trying again** on a different model when a run did poorly, which needs a way to choose that model.
5. **Cost against quality**: a knob that trades dollars and waiting for the chance of success.
6. **Task similarity**: "model M did well on tasks A and B, and C is like them, so M will probably do well on C."

Points 2, 4 and 5 are one decision with different inputs: pick the model whose predicted success and predicted cost best
fit this task's needs. Point 6 is what makes the predictions possible. Point 3 is the data they're made from. So the
design is a loop:

```
             ┌──────────────── task card (kind, importance, verification, size) ─────────────────┐
             │                                                                                    ▼
 parent ──▶ (1) delegate? ──yes──▶ (6) similar past runs ──▶ (2,5) predict success & cost ──▶ choose model
   ▲                                      ▲                         per candidate               │
   │                                      │                                                     ▼
   │                               outcome index ◀── (3) judgments: parent · tests · user ◀── subagent run
   │                                                                                            │
   └───────────── report ◀── ok ── judged ──── poor ──▶ (4) retry on another model (excluding the last) ─┘
```

## What the research says (and what we take from it)

- **Simple, local predictors work.** A well-tuned k-nearest-neighbors router over prompt embeddings matches or beats
  learned routers. The reason given is locality: models do similarly on prompts that embed close together
  ([Li 2025](https://arxiv.org/html/2505.12601v1); retrieval-based routing works from about 1% of the history in
  [ContextualRouter](https://aclanthology.org/people/christophe-bouvard/)). **We take**: kNN over task embeddings,
  with a Bayesian prior so that few neighbors mean "uncertain", not "certain".
- **Fancy routers often don't beat baselines.** Under one unified evaluation, most routing methods performed about the
  same, and several (commercial ones included) didn't reliably beat a simple baseline. A large gap to the oracle
  remained, and models were clearly complementary
  ([LLMRouterBench, 2026](https://arxiv.org/html/2601.07206); see also the
  [routing and cascading survey](https://arxiv.org/pdf/2603.04445) and [RouterBench](https://arxiv.org/pdf/2403.12031)).
  **We take**: every component must beat "always the same model" and "the model's average" on our own data before it
  is trusted, and the router reports which of these it currently beats.
- **Routing as a feedback loop.** For coding agents, routing works better as context → action → verified feedback →
  context than as a one-off classifier. Adding task-level performance statistics to a basic router helped
  ([Agent-as-a-Router, 2026](https://arxiv.org/pdf/2606.22902)). Contextual bandits cover the explore/exploit side
  ([online multi-LLM selection](https://arxiv.org/pdf/2506.17670), [neural bandits](https://arxiv.org/html/2508.09958v1)).
  **We take**: verified outcomes feed the next decision, with a small, budgeted amount of exploration.
- **Cascades, meaning cheap first and escalate on failure.** FrugalGPT-style cascades, agreement and self-consistency
  signals ([C3PO](https://arxiv.org/html/2511.07396v1),
  [agreement-based cascading](https://arxiv.org/pdf/2407.02348)) and decision-theoretic analyses
  ([is escalation worth it?](https://arxiv.org/pdf/2605.06350)) agree on three points:
  - Two levels capture most of the gain.
  - Escalation can also hurt a run that was fine ([signed rescue routing](https://arxiv.org/pdf/2609.07786)).
  - The quality of the failure detector decides whether cheap-first pays.

  **We take**: a retry ladder at most two deep, and an escalation decision that accounts for how reliable the judge is.
- **Judges are biased.** LLM judges prefer their own outputs ([self-preference](https://arxiv.org/pdf/2410.21819)). They
  also miss hallucinations and favor length on agent trajectories ([BabelJudge](https://arxiv.org/pdf/2606.22329)).
  Agents grading their own transcript mistake stagnation for progress
  ([self-evaluation bias](https://arxiv.org/pdf/2607.25152)). **We take**:
  - Grounded checks (tests, files, citations) count for more than opinions.
  - A judgment records how it was checked.
  - Parent and child on the same model is flagged.
  - Each judge model's reliability is measured against gold labels from the eval.
- **When multi-agent pays.** Anthropic's research system used about 15× the tokens of chat, and token usage explained
  most of the variance in performance. Multi-agent fits work that splits into parallel strands, and fits tightly
  coupled work like coding less well
  ([Anthropic](https://www.anthropic.com/engineering/multi-agent-research-system)). Cognition argues that parallel
  agents make conflicting decisions
  ([summary](https://www.morphllm.com/blog/multi-agent-systems.md)). **We take**: the delegation rules below favor
  read-only, separable work, and they count delegation's overhead.

## Where kurtkode stands today

- **When**: the model decides. The `task` tool's description says "searches or jobs that would take many steps and
  fill your context". No style template says anything about delegation.
- **Which**: the agent file's `model:`, else Settings → Subagent model, else the main model
  (`ChatController.subagentModel`). Nothing varies by task.
- **Judgment**: `AgentRunRecord.judgment` exists and is always empty. The report goes back with a note about how it
  ended (step limit, stopped, denied, cut off).
- **Retry**: none. The parent can call `task` again and gets the same model.
- **Cost and quality**: costs are recorded exactly (list price, tokens, time). Nothing about quality is recorded.
- **Data**: the user's sessions hold **no subagent runs** as of 2026-10-24 (the test sessions went to the Trash). Every
  prediction starts cold, so seeding matters (see "Seeding and exploration").
- **Available pieces**:
  - Run records with task text, model setup, outcome and totals.
  - The eval suite, whose scenarios have automatic checks.
  - Replay.
  - Checkpoints, to undo a subagent's edits.
  - The price list.
  - Measured speeds.
  - A local embedding model in LM Studio: `text-embedding-nomic-embed-text-v1.5`, 84 MB.

## 1. When to use a subagent

Delegation costs the parent tokens: writing the task (output) and reading the report (input), as COST_TRACKING_DESIGN
decided. It also adds a cold start, because the subagent re-reads what the parent already knows, and it carries a risk
of failure. It pays off in five situations.

| Reason | Signal | Typical agent |
|---|---|---|
| **Protect the parent's context** | The work would read much more than it reports: a broad search, several files to skim, a long log to scan. Expected reading of more than ~20% of the parent's free context, against a report of ~1–2k tokens | explore |
| **Parallel work** | Two or more independent read-only questions | explore, in the background |
| **Cost arbitrage** | The parent runs on an expensive model, the subtask is routine, and a cheaper model's predicted success clears the bar (§2) | any |
| **A specialist** | A custom agent fits the task, or a model has something the parent lacks (vision, a longer context, a tool) | custom |
| **A second opinion** | Reviewing a diff or checking a claim with a different model | general, or a reviewer agent |

It doesn't pay off in these cases:

| Situation | Why not |
|---|---|
| **Short tasks** (a few tool calls) | The overhead and the cold start cost more than the work |
| **Needs the conversation** | If the task prompt would have to restate most of the conversation, the parent should do it itself |
| **Tightly coupled edits** | Edits interleaved with the parent's own edits risk conflicting decisions. Writing subagents run one at a time already; prefer them for self-contained changes with a clear check (tests) |
| **Remote and private** | The work centers on files withheld from remote models and only remote candidates are available, or the parent is local and the only capable candidates are paid and over the user's budget |

How the rules reach the agent:

- **Words**: a new template, `delegation.md`, which the style templates place with `{{delegation}}`. It says when to
  delegate and when not, with the detailed style spelled out and the lean style short. Being a template, it can be
  tuned without a rebuild and A/B-tested with `kurtkode-eval --prompt-dir`.
- **Tool description**: the `task` tool's description moves into a template too, `tool-task.md`. It asks for a task
  card (§2).
- **Loop advice** (on by default, D7; Settings can turn it off): the loop already sees every tool result's size. When the parent
  has made, say, 6 or more read calls in a row that put more than 20% of its context limit into the history, it adds
  one note (`loopNote`): "This is broad reading; the explore subagent can do it and report back." This follows the
  existing nudges' rules: once, recorded, visible in the Journal.
- **Measuring the rules**: a subagent eval scenario, run with subagents on and off, and with `delegation.md` variants.
  It compares success, cost and the parent's peak context. That is the only honest test of "when", because the
  counterfactual of a real session can't be observed.

## 2. Which model: the router

### The task card

The `task` tool gains optional fields that the parent fills in. Small models may leave them out, and the router copes
by inferring them.

| Field | Values | Used for |
|---|---|---|
| `kind` | `search`, `explain`, `summarize`, `edit`, `refactor`, `fix`, `write-tests`, `review`, `research`, `run` | similarity (a strong feature), the bar |
| `importance` | `low`, `normal`, `high` | the success bar and the budget |
| `verify` | how success can be checked: a command (`swift test`), "files X exist", or `none` | judging (§3), choosing the escalation strategy |
| `tier` | `cheap`, `standard`, `strong` (a hint, optional) | a prior when the history is thin |

The card also carries derived fields, which the parent doesn't write:

- prompt size
- tools offered
- writes or not
- images
- the project's main language
- paths named in the task
- the parent's model
- the embedding of the task text

### Model configurations, not model names

An "arm" is a **configuration**: endpoint, model, reasoning effort, prompt style and the agent definition's hash. For
local models the quantization is part of it too. Gemma 4 26B through LM Studio at effort low is a different arm from
the same model at high, and from Gemma through OpenRouter. The run record already holds all of these
(`RunSetup`, `definitionHash`, `LocalModelInfo`).

**The routing pool** (Settings → Subagents) lists the configurations the router may pick, each enabled or not. Local
entries say "only while loaded" or "may load", the latter with the existing memory checks. **The router never unloads a
model.** Remote entries need a key. The pool, not every model in the catalog, keeps exploration bounded and spending
predictable.

### Filters before prediction

A configuration is dropped when any of these fails:

- it supports tool calls (its profile, its history)
- it has enough context for the estimated need
- it has vision, if the task has images
- it is available now: key present, loaded or loadable, not rate-limited (`RateLimits`)
- it is allowed by privacy: the user's "remote subagents" setting
- the run's and session's remaining budget (`CostMeter`) covers the predicted cost's upper quantile

### Prediction (point 6)

For each surviving configuration *m* and new task *x*:

1. **Neighbors**. Take past judged runs of *m*, ranked by distance *d(x, y)* (below). Keep the top *k* (start at 20)
   with similarity above a floor. Each gets the weight *wᵢ = exp(−dᵢ / h) · rᵢ*, where *rᵢ* is the reliability of that
   run's judgment (§3).
2. **Prior**. Use *m*'s success rate on the task's kind. With too few runs, back off to *m*'s overall rate, then to its
   tier's (a seed table from public coding benchmarks, coarse: weak, mid, strong).
3. **Cross-model difficulty** (the "similar tasks" transfer). Neighbors run by *any* model say how hard this kind of
   task is. If every model struggled on *x*'s neighbors, the prior moves down for everyone:
   `logit μₘ(x) = logit μₘ + γ · (logit s̄(x) − logit s̄)`. Here *s̄(x)* is the all-model success rate on *x*'s
   neighbors, and *s̄* is the overall rate. This is a one-parameter version of item response theory: a model's ability
   against a task's difficulty.
4. **Posterior**: a Beta distribution.
   - *α = α₀·μₘ(x) + Σ wᵢ yᵢ*
   - *β = α₀·(1 − μₘ(x)) + Σ wᵢ (1 − yᵢ)*
   - *p̂ = α / (α + β)*, the predicted chance of success.
   - *n_eff = Σ wᵢ*, so the interval narrows with real evidence.
   - Labels *yᵢ ∈ [0, 1]* come from judgments (§3).
5. **Cost and time**.
   - Tokens: the median over the neighbors' runs (any model), scaled by *m*'s measured verbosity relative to the
     others.
   - Dollars: tokens × the price list.
   - Time: prompt tokens ÷ *m*'s measured prompt speed, plus output ÷ its output speed. Both speeds come from cost
     entries' timings; on LM Studio prompt processing dominates, e.g. 117 tokens/s on muse-glimmer. Add the load time
     if the model isn't loaded.
   - Each estimate keeps an interval.

Later, once there are a few hundred judged runs, steps 3 and 4 can become a fitted logistic or IRT model (abilities per
configuration and skill cluster, difficulty per task, as in [EmbedLLM](https://iclr.cc/virtual/2025/poster/30322)).
They're only kept if they beat the kNN version on held-out data.

### Task similarity

The similarity measure combines what the tasks say with how models did on them. It stays simple until the data proves
a richer one works better.

- **Text**: embed the title and prompt **inside kurtkode, on the Mac's GPU** (D5, "Embeddings in the app" below). Two
  models are compared: Nomic Embed Text v1.5 (general text, prefix `clustering: `) and CodeRankEmbed (code-trained).
  Absolute paths are cut to their last two components, and numbers are masked. Embeddings never leave the Mac. Every
  task is embedded by both models, so `router eval` can compare them on the same data, and the better one is used.
  Fallback when neither is available: TF-IDF cosine over word and identifier tokens. It's weaker, but has no
  dependency.
- **Structure**: the card's kind (a mismatch costs a fixed distance), writes or read-only, verification type, and the
  log of the size ratio.
- **Distance**: `d = w_text · (1 − cos) + w_kind · [kinds differ] + w_write · [writes differ] + w_size · |log size ratio|`.
  The weights start at hand-set values and are later fit by leave-one-out prediction loss.
- **Behavior** (later): tasks are also similar when models succeed and fail on them alike (collaborative filtering
  over the configurations × tasks matrix). This catches tasks that look different but are equally hard for the same
  models.
- **Families**: clusters of task embeddings, named by their most common kind and words. They're for display ("on
  search tasks like this one: Qwen 7/8, Gemma 5/8"), not for prediction.
- **How we know it works**: the similarity measure is good exactly to the extent that it predicts outcomes. The check
  is leave-one-out Brier score and log loss of *p̂* against judged outcomes, compared with two baselines: model average
  only, and model × kind. `kurtkode router eval` reports all three. If similarity doesn't beat model × kind, the
  router uses model × kind, and says so.

### Choosing (point 5)

The default is a **success bar, then cheapest**. It's easy to explain and to set:

- **Bar**: candidates with *p̂ ≥ τ*. τ comes from the routing mode and the card's importance:

  | Mode | Importance low | normal | high |
  |---|---|---|---|
  | Thrifty | 0.6 | 0.7 | 0.8 |
  | Balanced | 0.7 | 0.8 | 0.9 |
  | Best | 0.8 | 0.9 | 0.95 |

- **Pick**: among candidates over the bar, the lowest expected cost.
- **Nobody clears the bar**: the highest *p̂*. If even that is below τ − 0.2, the parent is told it would probably do
  better itself.
- **Costs in two currencies**: dollars for remote models, waiting for local ones (local models are timed, never
  priced: COST_TRACKING decision 2). Expected cost is *dollars + θ · hours*, where θ is the user's **value of an hour of
  waiting**. θ is used only for routing; it's never recorded as a cost. (Decision D1 below.)
- **Cheap first, cascade-aware**. Starting on a cheaper model *c* and escalating to *s* on a detected failure beats
  starting on *s* when:
  - expected cost: *c_c + c_judge + [(1 − p_c)·recall + p_c·false_alarm] · c_s < c_s*
  - shipped quality: *p_c·(1 − false_alarm) + [(1 − p_c)·recall + p_c·false_alarm]·p_s ≥ τ*

  With a perfect judge this reduces to *c_c < p_c · c_s*. `recall` and `false_alarm` are the judge's measured
  reliability for this verification type (§3). A task with `verify: swift test` has a near-perfect judge, so
  cheap-first pays often. A task with `verify: none` has a poor one, so it pays rarely. The router considers both
  plans and records which it took.
- **Exploration** (bandit). To learn about configurations with little evidence, the router sometimes picks by
  **Thompson sampling**: a draw from each Beta instead of the mean. It does so only when all of these hold:
  - the importance is low or normal
  - the configuration's upper bound clears τ
  - the run's exploration share (default 10%) and the exploration dollar cap aren't spent

  Exploring on a local model costs only time, so it's cheap and goes first.

### Precedence

Highest first:

1. The agent file's `model:`, a pin.
2. A `model` the user named in the conversation, passed by the parent.
3. The router, if on.
4. Settings → Subagent model.
5. The session's model.

With the router off, kurtkode behaves as today.

### Advisory first

The router runs in **advisory mode** before it acts. It records what it would pick and why, but the run still uses
today's model. Advisory decisions are compared with outcomes, and the router acts only once it beats the baselines.

## 3. Judging a run

### Four kinds of evidence

1. **Grounded checks** (automatic, every run, free):
   - The stop reason: completed, step limit, cut off, denied, stopped.
   - The step count against the limit.
   - Tool errors.
   - Repeated identical calls.
   - An empty report.
   - **Citations that resolve**: every `path:line` in the report names an existing file and line. This is cheap and
     catches made-up findings.
   - **Claims against the file record**: files the report says it changed against the files that actually changed
     (`RunOutcome.filesChanged`).
   - **The card's `verify` command**: after a writing run, under the same sandbox and approval rules as any command,
     and only when the card names one.
   - Later evidence: the user undoes its edits, or the parent re-delegates the same task.
2. **The parent's rating** (every run the parent used). This is a new tool, `rate_task`, defined in a template:

   | Field | Values |
   |---|---|
   | `run` | the task call's id |
   | `verdict` | 3 done and right as far as checked · 2 done, minor gaps · 1 partial, needed real rework · 0 failed, wrong, or harmful |
   | `checked` | `ran-tests` · `read-the-files` · `spot-checked` · `not-checked` |
   | `issues` | tags: `incomplete`, `wrong-facts`, `made-up`, `ignored-instructions`, `out-of-scope`, `broke-things`, `slow`, `too-long` |
   | `note` | one or two sentences |

   The `task` result asks for a rating once the report has been used. At the end of the parent's run, the loop asks
   once for any missing ratings, all of them in one note. Ratings are cheap: a short tool call on a cached prompt.
3. **A grader model, for `importance: high` runs** (D2). A configuration chosen in Settings, never the child's own
   model, gets the task, the report, the grounded checks and the files the report cites. It answers in the same schema
   as `rate_task`. Its requests are recorded like any other (wire log, a cost entry with the purpose `grading`), and
   its full request and reply are kept with the judgment.
4. **The user's rating** (optional, and the most trusted): thumbs and a verdict in the Agents tab and the Debug
   window's subagent section, or `kurtkode judge RUN --verdict N [--note]`.

### Record format

Judgments are appended as a new record type, `judgment` (judge kind and model, verdict, checked, issues, note, grounded
signals, time). They go in the child session, with a copy in the parent's session so that listings needn't open every
child. **Every judgment is kept**, never replaced or pruned (D2): the parent's, the grader's (with its full request
and reply), the user's, and each set of grounded checks. They're training data for later fine-tuning, of the judges
and of the predictor. A run can have several; the predictor's label uses the latest from each judge, and
`kurtkode judgments --json` exports them all with the task, the report and the run record. `AgentRunRecord.judgment` stays as the
summary written at the run's end: the grounded signals. Older builds skip the unknown record type, as usual.

### The label the router learns from

*y* comes from the most trusted judgment available, in the order user > test > grader > parent:

- the verdict divided by 3
- forced to 0 by a grounded hard failure: no report, made-up citations, or tests that fail

Each label carries a reliability *r*:

- 1 for the user and tests
- for the parent and the grader: their measured agreement with gold labels (below); the parent's is lowered further for
  `not-checked` and when parent and child run on the same model (self-preference)

### Calibrating the judges

The eval's subagent scenarios have automatic gold checks. On them, the parent's verdicts are compared with gold, per
parent model and per verification type. That gives each judge's recall and false-alarm rates, which the cascade rule
(§2) and the label weights use. `kurtkode router eval` prints this table.

## 4. Trying again

| Failure | Who retries | How |
|---|---|---|
| **Hard**: no report, the run stopped on an error, a rate limit or a model error, made-up citations | The loop, automatically, once (D3) | Next model by the router, excluding the failed one |
| **Soft**: parent verdict ≤ 1, or the `verify` command fails | The parent, by calling `task` again with `retry_of: <call id>` | The router excludes the failed configuration and asks for a higher success bar (the next τ up) |
| **The user stopped it**, or denied an action | Nobody | As today: carry on without it, and don't take that action |

- **What the next attempt gets**: the original task, plus "A previous attempt was judged inadequate: <the parent's
  issues and note>". The failed report is included only when the parent says so, because a wrong report can anchor
  the next model.
- **Edits are undone first**: a failed *writing* run's edits are rolled back with its checkpoints before the retry,
  and the parent is told.
- **Limits**: at most two retries per task, a ladder that goes up and never sideways to a weaker tier, and the budget
  checks in §2. After that, the parent does the task itself or asks the user.
- **Retries are valuable data**: the chain (`attemptOf`) gives head-to-head results on the *same* task, the strongest
  evidence the outcome index gets. A retry can also make things worse (signed rescue), so it is judged like any run.

## 5. Cost against quality: the user's controls

- **Routing mode**: Thrifty, Balanced or Best (the table in §2), in Settings → Subagents, `/route`, and CLI `--route`.
  It is one knob that most users never touch.
- **Importance**: per task, from the parent. Setting it is guided by the delegation template ("high: its result
  decides an irreversible action or a user-facing answer").
- **Value of waiting (θ)**: dollars per hour, for local against remote (D1).
- **Hard limits**: the run and session spending limits that exist now, a per-subagent cap, the exploration share and
  the exploration cap.
- **What each choice cost and bought**: every routing decision is recorded, and the Agents tab shows the chosen model,
  *p̂* with its evidence ("7/8 on 8 similar tasks"), the expected and actual cost, and the rating. A later "Models for
  tasks" window plots each task family's configurations as success against cost (the Pareto front, with error bars).

## Records and code

### New records

All of these are JSON Lines and appended. Unknown record types are skipped by older builds.

| Record | Where | What |
|---|---|---|
| `route` | parent session | Task card, candidates with *p̂*, interval, *n_eff*, predicted cost and time, filters that dropped others, the plan (direct or cheap-first), exploration flag, mode, chosen configuration, router version, advisory or acting |
| `judgment` | child, copied to parent | as in §3 |
| run record `attemptOf` | child | the earlier attempt this one retries |

### The outcome index

The index lives at `~/Library/Application Support/kurtkode/routing/outcomes.jsonl`. It is a **derived** index (one line
per judged run: configuration, card, embedding, label, reliability, cost, time), always rebuildable from session files
with `kurtkode router rebuild`. Session files stay the source of truth. Embeddings are cached by task hash.

### Code

| Piece | Where (new unless noted) |
|---|---|
| Task card, `rate_task`, `retry_of` | `Agent/Subagents.swift` (the `task` tool), `Agent/TaskRating.swift` |
| Grounded checks | `Routing/GroundedChecks.swift` |
| Embeddings (in-app: swift-embeddings on the GPU; TF-IDF fallback) | `Routing/TaskEmbedder.swift`; models in `~/Library/Application Support/kurtkode/models/` |
| Outcome index, neighbors | `Routing/OutcomeIndex.swift` |
| Predictor (prior, kNN Beta, difficulty shift, cost and time) | `Routing/Predictor.swift` |
| Router (filters, bar, cascade rule, Thompson, records) | `Routing/Router.swift`; called from `SubagentSetup.resolveModel` (changed: takes the card) |
| Retry and rollback | `Agent/Subagents.swift`, `Session/Checkpoints.swift` |
| Templates | `Prompts/delegation.md`, `Prompts/tool-task.md`, `Prompts/tool-rate-task.md` |
| App | Settings → Subagents (pool, mode, θ, exploration); Agents tab (route, rating, thumbs); Debug subagent section |
| CLI | `kurtkode judge`, `kurtkode route "task…" [--kind]` (dry run), `kurtkode router eval / rebuild / seed`; `kurtkode runs` gains judgment columns |
| Eval | subagent scenarios and a task bank with gold checks (`EvalKit/Scenarios.swift`, `Fixtures.swift`) |

## Seeding and exploration

**Measured priors (2026-10-25, COST_FLOOR_RESULTS.md):** on the bank plus a 14-task hard tier, `inclusionai/ling-3.0-flash`
passes 99% (interval 97–99%, 480 runs) at $0.0002 a task, the cheapest of 499 OpenRouter configurations above 95%.
deepseek-v4-flash-0731 and claude-haiku-5.5 are the next ones. Cheap models fail broad reading (survey, log sweep) on
their own. Delegating that reading to them cuts argon's cost by 63% at equal quality, but makes frugal parents
(Sonnet 5.5) dearer. The cheapest adequate judge is claude-haiku-5.5 by the parent path (kappa 0.67, against argon's 0.71).

There is no history, so the first predictions are priors. Data comes from three sources.

1. **A task bank in the eval** (the main early source). It holds 30–40 small tasks shaped like real delegations, each
   with an automatic gold check:
   - find every caller of a function
   - explain a module, with facts that can be checked
   - summarize a log for a planted error
   - rename across files
   - fix a failing test
   - write tests that must pass
   - review a diff with a planted bug
   - extract numbers from files

   Every pool configuration runs each task two or three times. This also calibrates the judges, because each parent
   model rates each run as well. Local models cost only time. **Remote runs cost money and need the user's approval**:
   with the pool of D6 the only paid model is Gemini, so for example 35 tasks × 1–2 Gemini configurations × 2 trials
   ≈ 70–140 runs at $0.01–0.07 each, roughly $1–10, estimated before running with `cost calibrate`-style dry runs.
2. **Real use**: every judged subagent run.
3. **Shadow runs** (on, D4): for a read-only task, a second configuration runs the same task in the background, and
   its report is judged by grounded checks and, cheaply, by the parent. The parent never sees a shadow's report, so
   shadows can't change the session's outcome. Guardrails, since shadows share the user's machines:
   - free models only: this Mac's LM Studio and the LAN server (bang); bang goes first, because it doesn't compete
     with this Mac's memory
   - only a model that's already loaded; never one loaded for a shadow, and never an unload
   - only while that model has a free parallel slot, so a shadow never queues ahead of real work
   - paused whenever this Mac's free RAM is below 25%
   - read-only tasks only
   - a daily cap on shadow runs (default 30), in Settings

How much data is needed: a personal tool makes perhaps tens of subagent runs a day at most. With priors and the
cross-model difficulty shift, kNN is useful from about 5 judged neighbors per configuration and kind. The fitted
models wait for a few hundred runs. The router says how much evidence lies behind each prediction, and `router eval`
says whether it beats the baselines yet.

## Phases

Each phase builds, passes its tests and is checked, as before.

| Phase | Delivers | Points |
|---|---|---|
| **P1 Judging** | Task card fields, `rate_task` and the run-end ask, grounded checks (citations, claims, verify command), `judgment` records, user thumbs and `kurtkode judge`, `runs` columns. No routing change | 3 |
| **P2 Delegation rules and a subagent eval** | `delegation.md`, the `task` description as a template, the optional loop advice; subagent scenarios and the task bank with gold checks; judge calibration report | 1, 3 |
| **P3 Similarity and the outcome index** | The in-app embedder (swift-embeddings, both models; their download with the user's approval), index, neighbors, `kurtkode route` dry run, `router eval` with leave-one-out, both baselines, and Nomic against CodeRankEmbed | 6 |
| **P4 Router, advisory** | Pool, filters, predictor, bar and cascade rule, `route` records shown in the Agents tab and Debug; still runs today's model | 2, 5 |
| **P5 Router, acting; retries** | Routing modes, θ, exploration with caps; `retry_of`, automatic retry of hard failures, rollback of failed edits, the ladder | 2, 4, 5 |
| **P6 Seeding** (with the user's spending approval) | Task bank runs across the pool; optional shadow runs | data |
| **P7 Later, on enough data** | Fitted ability and difficulty model, behavioral similarity, learned distance weights, the "Models for tasks" window | 6 |

## P1 as built (2026-10-24)

**What's in it**

- **The task card**: `task` takes `kind`, `importance`, `verify` and `tier`, all optional and lenient (unknown values
  are dropped). The card is kept on the run's end record and its run record (`RunTask.card`), and in `CostScope`. A
  `verify` command is added to the subagent's task ("when you're done, run it and say whether it passed"), so the
  run's own tool results show whether it passed.
- **Grounded checks** (`GroundedChecks`, `Agent/Judging.swift`), at every run's end:
  - how it stopped, its steps against the limit, tool errors, repeated calls
  - citations that don't resolve: three forms, `path:line`, a path then "line N", and a table row with the path and
    a number cell
  - changed files the report doesn't name
  - the `verify` command's exit status
  - hard failures: no report, stopped on an error, made-up citations (at least 2, and at least half), a failed check

  Problems are added to the report the parent reads (`[Automatic checks: …]`). The subagent preamble now asks for
  `path:line` citations.
- **Judgments**: a new record, `judgment` (`RunJudgment`), appended to the run's session and copied to the parent's
  through a new event (`.judged`). Every judgment is kept; the label uses the latest from each judge
  (user > a hard failure > grader > parent).
- **`rate_task`**: offered with `task`, so the parent can rate a run while it works. At the end of a run that used
  subagents, any run it didn't rate gets a **rating request aside from the conversation**: nothing in it enters the
  transcript, and it has the same prefix, so it reads from the cache. It's a short side loop: read-only calls run (up
  to 4 requests) so the parent can look before it rates. These requests are cost entries with the purpose `rating`.
- **Is the claimed check real?** Each parent rating records whether its own calls after the report back up `checked`
  (`checkedConfirmed`, `evidence`: the read and bash calls). A rating that says "read the files" with no call after
  the report shows as *unconfirmed* everywhere.
- **The grader**: Settings → Subagents → "Grade important tasks on". When a task's card says `importance: high`, the
  grader gets the task, the report, the checks, and excerpts of the cited lines, then answers with `rate_task`. It is
  never the run's own model. Its full prompt and reply are kept with the judgment, and its cost is the parent's
  (purpose `grading`).
- **The user's judgment**:
  - the app: the Agents tab shows each run's judgments and a **Rate** menu
  - the CLI: `kurtkode judge RUN --verdict 0-3 [--issues …] [--note …]`
- **Exports**: `kurtkode judgments [--json]` lists every run and its judgments; `--json` gives the task, card, report,
  run record and every judgment in full, for tuning. `kurtkode runs` gains columns: card, label, each judge's verdict,
  the checks' problems, hard failure.
- **Tests**: 400 pass with 11 known issues, 10 of them new (`JudgingTests`). Two cost tests now count the rating
  request. The app and the CLI build with no warnings.

**What live runs showed** (the debug CLI on the LAN server's qwen3.5-9b, five delegations in a small project):

- The model filled in the card (kind `search`, importance `normal` or `high`) and always delegated.
- **The parent rated every run 3/3. In three of four ratings that claimed a check, it had made none.** One rating's
  note said "Verified by reading the reported files" when it hadn't read anything. That's self-evaluation bias, and
  `checkedConfirmed` now records it. Parent ratings are therefore weak labels until calibrated (P2), as the design
  expected.
- Asked to rate "from what you checked", the model once tried to read the files first. The first version of the
  rating request ignored those calls and recorded nothing. That's why it became a side loop with read-only calls.
- Reports put locations in tables, or wrote "at line 17", instead of `path:line`. That's why the checks gained the
  other two forms.
- The grader wasn't tried live: it needs a grader model chosen in Settings, and that's the user's setting.

**Not in P1**

- The Debug window's subagent section doesn't show judgments.
- `rate_task`'s and `task`'s descriptions are still in code; they move to templates in P2.
- The eval doesn't collect judgments or compare them with gold yet; that's P2's calibration.

## P2 as built (2026-10-24)

**What's in it**

- **Delegation rules as a template.** `delegation.md` goes in both styles (detailed, or one line with `lean`) through
  `{{delegation}}`, inside `{{#subagents}}`, so only prompts that offer the task tool carry it. They say when to
  delegate and when not, that a task must stand alone, to fill in the card, to check what a report claims, and to rate
  it. `FrozenSystemPrompt` keys get `|sub`. Prompts without subagents are unchanged, checked byte for byte on the 288
  combinations again. A session with subagents on gets the new text, so it rebuilds its prompt once.
- **Tool descriptions as templates**: `tool-task.md` (with `{{agents}}`) and `tool-rate-task.md`, rendered with the
  project's and the user's overrides. The defaults keep the old wording exactly.
- **Loop advice** (D7, on by default; Settings → Subagents → "Suggest delegating broad reading"; `delegationAdvice`).
  After 6 or more read calls in a row (read_file, grep, glob, list_dir) whose results add up to a fifth of the context
  limit, the last result gets `note-delegate.md`'s note, once a run, and the result's notes record it.
- **The rating side loop is one function**, `AgentLoop.ratingSideLoop`. The end-of-run request and the eval's judge
  calibration both use it, so calibration measures the production path.
- **The task bank** (`EvalKit/TaskBank.swift`): 16 tasks covering all ten kinds, built on old fixtures and five new
  ones (a log, a package to rename in, a stats module, a diff to review, a checksum script, sales CSVs). Each has a gold
  check computed from the fixture. A test checks every gold check against a known-right outcome (must pass) and an
  idle one (must fail), with no model involved. 30–40 tasks remain the goal.
- **`kurtkode-eval --bank …`** runs each task directly as a subagent would: the agent's tools, the subagent prompt with
  default templates, the task with its card's check.
  - It records gold, the grounded checks, cost and the transcript.
  - Each judge in `--judges` rates every run two ways (`--judge-paths`): `parent` (the end-of-run rating, with a
    conversation of the request, the task call and the report) and `grader`.
  - `--degrade` adds a known failure per passing run: the report's multi-digit numbers are changed (lines, amounts,
    times, names like Heron42) and a change task's files are reset. The copy is used only if gold then fails.
  - The calibration table (`JudgeCalibrationRow`) shows, per judge and path: verdicts, agreement with gold, failures
    caught, passes failed, and claimed checks it didn't make. The automatic checks are a row too.
- **`--subagents on|off|both`** runs any scenario with the task tool on the same model, recorded in a throwaway store.
  A new scenario, `survey`: 16 meeting notes, five of which postpone something, each in different words, with two
  distractors that mention postponing only to reject it. The context is capped at 16k.
- **Fixes from the runs.** The grader's `checked` is now what it was shown, not what it says: it has no tools, yet
  claimed `ran-tests`. A grading without a verdict is kept, with the reason and the reply, and never hides another
  judge's label.
- **Tests**: 408. The only failure in a full run was `aServerThatExitsIsMarkedFailedUntilRestarted`, the known
  timing-dependent test, which passed alone. The app and the CLI build with no warnings.

**What the runs showed** (bang's qwen3.5-9b as the subagent, the parent and the grader; results in `eval-results/`)

- **The bank: 16 of 16 tasks passed** (one first showed as a failure; it was a bug in the gold check, found by reading
  the run, and fixed).
- **Judges**:
  - The parent path read the files before rating in 10 of 14 rated runs. Asked inside a real run earlier, it had
    checked in 1 of 4.
  - It claimed checks it didn't make in 4 of 16.
  - Both paths gave no verdict on review-diff (importance high), once each.
  - With no failures among the runs, nothing could be said about catching failures. That's why `--degrade` exists;
    its results:
    - 13 degraded copies failed gold and were judged. 3 didn't count, because gold still passed: callers-reserve and
      calc-bugs-explain have no multi-digit facts to corrupt, and review-diff's answer doesn't depend on numbers.
    - **The grader caught 54% of the known failures and the parent 44%. Neither failed a good run (0 false alarms).**
    - The grader caught wrong lines, names and times, because it sees the cited lines. It missed every failure it
      couldn't see: a change task's files reset (fix-calc, add-median, write-pricing-tests), and numbers it would have
      had to compute (run-script, sum-csv).
    - The parent caught the reset rename (it read the files) and wrong numbers it could look up. It gave no verdict on
      5 of 29.
    - The checks row counted only the real runs in this run (the degraded copies' checks weren't recorded yet; now they
      are).

    So a judge that reads catches reported facts that are wrong, and no judge catches work that is said to be done but
    isn't, unless it runs the check. The rating side loop allows only read-only calls, so the parent can't run `verify`
    there. Letting it run exactly the card's `verify` command is the next step for judging.

**After P2: the parent may run the check** (2026-10-24, after `ba06208`)

- The rating side loop now also runs a bash call whose command is exactly an unrated task's `verify` (trimmed). It goes
  through the loop's own `authorize`: hooks, permission rules, the danger check, the mode, the user's approval in Ask
  mode. Any other command is refused, with the allowed checks named. The request names each task's check.
- Only calls that actually ran count as evidence for `checkedConfirmed`. Before, a refused call counted.
- **Re-run of the degraded bank** (`eval-results/bank-degrade-verify-…`):
  - The parent ran the check twice, once on a good run (3/3) and once on the degraded fix-calc.
  - On the degraded fix-calc it found the failure, writing "it didn't apply the changes — calc.py still shows the
    buggy code", and still rated it **2/3**. It found the failure, then mis-scored it.
  - Failures caught: parent 40%, grader 46% (44% and 54% before; 13 known failures each, so the differences are
    noise). Still no false alarms. The checks row, now with the degraded copies, catches 15% (shifted citations).
  - The subagent passed 14 of 16 this time (16 of 16 before), which is the size of run-to-run variation.
- **What this says**: running the check doesn't help when the judge doesn't act on what it sees. Two remedies:
  1. **Make the re-run check grounded.** When the check runs before a rating and fails, record a `checks` judgment
     with a hard failure. The label then becomes 0 whatever the verdict says, which is the design's rule that grounded
     beats opinion. Better still, run each changing run's `verify` once more at the end of the parent's run whether or
     not the parent asks (authorized the same way), so no judge is needed for it.
  2. **Tighten the rubric**: "if the work isn't actually done or its check fails, the verdict is 0 or 1", in
     `tool-rate-task.md` and the rating request.
- **Delegation: none at all.** Over six survey runs with the task tool offered (2 on the first, grep-friendly version
  and 4 on the notes version), qwen3.5-9b never called it.
  - It ignored the loop's advice when it fired.
  - On the notes survey it searched for keywords and stopped: 1–2 of 5 found, with subagents off or on.
  - On the first version, with subagents on, it read every file to verify a correct grep result (29 calls,
    2 compactions, 124 s, against 2 calls and 18 s without subagents).

  Whether the rules make a stronger model delegate, and whether that helps, needs a stronger model on the same
  scenario: in the D6 pool, that's Gemini (paid).

**Not in P2**

- The bank has 16 tasks, not 30–40.
- A paid model hasn't been run on the bank or the survey.
- The Debug window still doesn't show judgments.

**Then: the check re-run as grounded, and a tighter rubric** (2026-10-24)

- **The re-run.** At the end of the parent's run (before the ratings), each of the run's tasks with a `verify` gets
  its check run once more by kurtkode, authorized like any command (`AgentLoop.runCheck`). It's recorded as a new kind
  of grounded judgment, `recheck` (`GroundedChecks.recheck`). A failure is a hard failure, so the label is 0 whatever
  any rating says. The rating request tells the parent what happened ("run again just now: it FAILED, exit 1"). It
  shows in the Agents tab, and `kurtkode runs` has a `recheck_exit` column.
- **The rubric**: "If the work isn't actually done, or its check fails, the verdict is 0 or 1, however good the rest
  looks." It's in `tool-rate-task.md`, the verdict's description and the rating request, and in the grader's prompt
  too (added after the run below, so not measured there).
- **The eval does the same**: each bank run's check is re-run, the degraded copy's too (a change task's files are
  reset, so its re-run fails). The judges see the run as a real parent would, and hear of the re-run in the rating
  request. The stored checks include it.
- **Re-run of the degraded bank** (`eval-results/bank-degrade-recheck-…`, 12 known failures, qwen3.5-9b):

  | | Before (two runs) | Now |
  |---|---|---|
  | Parent: failures caught | 44%, 40% | **82%** |
  | Parent: passes failed | 0%, 0% | 7% (1 run) |
  | Grader: failures caught | 54%, 46% | 46% (rubric not yet in its prompt) |
  | Checks, with the re-run: failures caught | 15% | 31% |

  The combined label (a grounded hard failure is 0, else the parent's verdict) put 11 of the 12 known failures at
  ⅓ or below. The one it missed is run-script, whose wrong number nothing re-computes.
- **Why** (from the per-run table): the parent now scores what it finds. It rated the degraded explore tasks 0–1,
  where before it rated them 2–3, so the rubric did most of the work. The re-run caught the undone fix-calc and
  add-median (and an over-strict judge can't wave them through). It doesn't catch work whose loss leaves the check
  passing: a deleted new test file (the remaining tests still pass), or an undone rename (behavior unchanged).
- **Caveats**: one run of 12 known failures and about 15 good runs, one 9B model as subagent and judge. The direction
  is clear; the size isn't settled.

**The evaluation** (EVAL_PLAN.md, EVAL_RESULTS.md, 2026-10-24 and 25). Record once, judge many; 34 tasks; 6 subagent
models; 4 judges × 2 paths; 7 failure kinds; delegation decisions. In brief:
- Gemini models pass the whole bank, which is too easy to rank them.
- argon's parent path is the best judge (kappa 0.71, no good runs failed).
- The re-run check catches all undone work.
- Nothing catches edits outside the task: the card needs a scope.
- No model delegates on its own (3 of 36 where it would help).

The next steps are listed at the end of EVAL_RESULTS.md.

## Decisions (2026-10-24, the user)

- **D1 Waiting against dollars**: **a value of an hour of waiting**, θ, used only for routing and never recorded as a
  cost. It's a setting (Settings → Subagents; `RunSettings.routingHourValue`). It starts at $5 an hour, a placeholder
  to be adjusted as runs show how the choice works out.
- **D2 Who judges**: **the parent and grounded checks for every run, plus a grader model for `importance: high`
  runs**. **Every judgment is kept** (§3) for fine-tuning later. The user's ratings override all of them.
- **D3 Automatic retries**: **yes**: hard failures are retried once on another model, within the budget.
- **D4 Exploration**: **exploration and shadow runs**. Thompson exploration on up to 10% of low and normal runs, with
  paid exploration capped at $0.50 a day. Shadow runs on free models, with the guardrails in "Seeding and exploration".
- **D5 Embeddings**: **in the app, on the Mac's GPU, not through LM Studio**. Nomic Embed Text v1.5 for general text,
  and a code embedder (CodeRankEmbed) tried against it. See "Embeddings in the app".
- **D6 The pool**: **this Mac's LM Studio models, the LAN server (bang), and Gemini** (Gemini 3 Flash through the
  user's key). Claude and OpenRouter are out for now. The pool is a list in Settings, adjusted as we learn.
- **D7 Loop advice** to delegate broad reading: **built and on**. The subagent eval still measures it.
- **D8 Scope**: **subagents only**. The user's thumbs on main runs go into the same index for later.

### Embeddings in the app

- **Engine**: [swift-embeddings](https://github.com/jkrukowski/swift-embeddings) (MIT). It runs `nomic_bert` models
  with Core ML's `MLTensor` (macOS 15, which AgentCore already requires) on the CPU and GPU (`computePolicy:
  .cpuAndGPU`). Its instructions build and test it with plain SwiftPM, so the CLI should get it too: to be confirmed
  when it's first built. MLX Swift was the alternative, but it can't build its Metal shaders with `swift build`, which
  is how the CLI is built, and its embedding library has no `nomic_bert` model that I could find.
- **Models**: both are 137M-parameter `nomic_bert` encoders, 12 layers, 768-dimensional, so one engine runs both:
  - **Nomic Embed Text v1.5** (Apache 2.0): general text; task prefixes (`clustering: `, `search_query: `); vectors
    can be cut to 256 or 128 dimensions with little loss.
  - **[CodeRankEmbed](https://huggingface.co/nomic-ai/CodeRankEmbed)** (MIT, 8,192-token context): trained for code
    retrieval on 21M examples. Its query prefix is "Represent this query for searching relevant code".
- **Download**: each model is a 547 MB float32 safetensors file plus its tokenizer, about 1.1 GB for both. Each
  download needs the user's go-ahead with its size, as always. The models live in
  `~/Library/Application Support/kurtkode/models/`, shared by the app and the CLI, and are loaded on first use.
- **Memory**: roughly 0.6 GB per model loaded in float32, and half that if converted to float16. Both are loaded only
  while embedding, and released after a minute idle, so they don't sit beside the user's LM Studio models.
- **LM Studio's Nomic** (the Q4 copy already downloaded) isn't used. It stays a possible fallback if the in-app
  engine fails.

## Risks

- **Parents that can't judge.** Small local parents may rate everything 3. Calibration finds this, and their labels get
  low reliability. Grounded checks still separate clear failures.
- **Drift.** Models change behind the same name (OpenRouter providers, new versions). Neighbors are weighted by age, a
  half-life of perhaps 60 days, and the provider is part of a remote configuration's identity where it's pinned.
- **Overfitting to the task bank.** Bank tasks are labeled `source: eval` and their weight shrinks as real judged runs
  accumulate.
- **Cost of judging.** `rate_task` calls add parent tokens, which count as the parent's cost and are recorded with the
  purpose `rating`, so their cost is visible and can be weighed.
- **Complexity without benefit.** LLMRouterBench's warning. Every layer must beat its baseline in `router eval`, or it
  is switched off.
