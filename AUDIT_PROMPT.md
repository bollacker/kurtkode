# Prompt for the next session: an audit of kurtkode's cost-optimization architecture

Paste everything below the line into a new session started in `~/git/kurtkode`.

---

You are auditing kurtkode, a native macOS + CLI coding agent at `~/git/kurtkode` whose reason to exist is to let one
session mix models from several sources (LM Studio on this Mac and the LAN, OpenRouter, Anthropic, Gemini) and spend
as little as the work allows. Over Phases 0–3 of `GAP_ANALYSIS.md` it gained a rich set of cost features. Your job is
an **independent, evidence-based judgment of that cost-optimization architecture**, not more feature work.

## Answer three questions

1. **How much could it actually save?** Against clear baselines: always the session's model, always a frontier model
   (Opus 5.5 / Sonnet 5.5 / gemini-4-argon), always Haiku 5.5. Do it per mechanism and combined, on the workloads we
   have (the 34-task bank, the 14-task hard tier, the delegation scenarios, this Mac's own sessions) and on a realistic
   mix you define and justify. Give ranges with their uncertainty. Keep measured numbers apart from modeled ones. Count
   the hidden costs: judges, reviews, retries, model switches (history re-read uncached), cache misses, prompt overhead
   (the skills listing, tool definitions), and the user's time.
2. **What should be improved?** Rank the improvements by expected savings (or quality kept) against effort and risk.
3. **What is missing or wrong?** In the design, in the evidence, and in the code: cost accounting that double-counts,
   misses or mislabels requests; estimates that are off; priors that are stale; claims in the docs that the code or
   the data don't support.

## Read first, in this order

1. `HANDOFF.md`: "Start here", "Working conventions with this user", "Hard-won facts". These are binding.
2. `COST_ARCHITECTURE.md`: every cost mechanism mapped to its code, default and evidence; the lessons so far; open
   questions. It's your map. **It was written by the team being audited, so treat its claims as claims to check.**
3. `GAP_ANALYSIS.md`: Part 2 Theme A, the Phase 2 and Phase 3 plan, "as built" and "measured" sections.
4. `COST_FLOOR_RESULTS.md`, `EVAL_RESULTS.md`, `SUBAGENT_ROUTING_DESIGN.md` (its research survey and decisions D1–D8),
   `COST_TRACKING_DESIGN.md`. `FUNCTIONAL_TEST_RESULTS.md` "Round 6" and "Round 7" for the defects found already.

## How to work

- **Be independent.** Check the code paths behind each claim you rely on (`AgentCore/Sources/AgentCore/Agent/`,
  `LLM/CostEntry.swift`, `Models/ModelPool.swift`, `Agent/Escalation.swift`, `Agent/Review.swift`, `EvalKit/`).
  Reproduce key numbers before building on them: `kurtkode cost report --eval STORE`, `kurtkode-eval --trigger-sim`,
  `--review-sim`, `--retry-sim` over `eval-results/runs/` (about 19,000 stored runs with transcripts, fixtures, gold
  results and, for some, judgments). Read failure clusters, not only rates.
- **Search the literature** on the web (2024–2026): cascades and routing (FrugalGPT and successors, RouterBench,
  LLMRouterBench, agreement- and confidence-based cascades, "is escalation worth it"), LLM judges and their biases,
  self-verification and test generation as failure detectors, cost of agentic coding (token use, caching,
  multi-agent overhead), and what Claude Code, Codex and similar tools do about cost. Compare kurtkode's choices with
  what the evidence says; cite with links.
- **Design experiments that can support or refute each important claim**: for each, the hypothesis, the data, the
  method, the metric, the decision rule, and the cost in money and time. Prefer offline replays over stored runs
  (free) and the local model. **Run the free ones** and report their results. List the paid ones with estimates for
  the user to approve. Candidates worth considering (yours may be better):
  - a savings model of a realistic workload, built from stored runs and `cost whatif`, with sensitivity analysis;
  - cheaper failure detectors replayed on stored runs: agreement between two cheap models' answers,
    self-consistency, the reviewer on answer tasks, log-probabilities where a server gives them;
  - whether the shipped priors still hold at today's prices (OpenRouter `/models` needs no key);
  - whether the benchmarks discriminate (harder or real tasks: what would a fair test set look like);
  - the router design (P3, not built): would kNN over task embeddings beat "always ling" on the stored runs?
- Use subagents for parallel reading and literature search if useful; keep their briefs narrow, verify what they
  bring back.

## Rules (the user's; don't break them)

- **Ask before downloading anything and before any paid API call.** Give an estimate and use a `--max-cost` (every
  paid eval mode has one). **Warn the user right before anything will raise a Keychain prompt** (a freshly built
  binary reading a saved key does), and use one process per paid run.
- **Local models**: check `lms ps` (`~/.cache/lm-studio/bin/lms`) and free memory first. If nothing is loaded, you may
  load `google/gemma-4-26b-a4b-qat --context-length 32768 --parallel 1` and must unload it after (by name, never
  `--all`). **Never load, unload or reload a model the user has loaded**; use it as it is, and pass `--no-load` to the
  eval. Use `-m lmstudio:MODEL` in the CLI (an unknown name falls through to a keyed endpoint) and
  `KURTKODE_NO_KEYCHAIN=1` for the CLI and test app instances.
- **Keep waits short** and report partial results; long runs go in the background.
- **Don't change product behavior.** Measurement tooling in `EvalKit`/`kurtkode-eval` is fine; commit it separately
  with tests, and say so. Don't propose trimming the skills listing or tool descriptions for prompt size (the user's
  call, 2026-10-26: small models have large contexts).
- Test sessions go to `~/.Trash/kurtkode-test-*`. The user commits by asking; commit the audit when it's done.

## Deliverable

`COST_AUDIT.md` in the repo, written plainly:
1. **Verdict** in a paragraph, and the savings estimate (ranges, per baseline and workload).
2. **Findings**, most important first, each with its evidence (code path, data, replay, literature) and severity.
3. **Improvements**, ranked: expected savings or quality kept, effort, risk, and how to measure them.
4. **Missing or wrong**: design gaps, accounting bugs (with a probe each where you can), stale data, unsupported claims.
5. **Experiments**: those run (method, results) and those proposed (with cost estimates, for approval).
6. **Literature**: a table of sources and what each implies for kurtkode.
7. **Decisions for the user**, framed as options with a recommendation.

Then update `HANDOFF.md` ("Start here", "Next steps") and finish with a short plain report and the one question that
most needs the user's answer.
