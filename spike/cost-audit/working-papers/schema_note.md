# eval-results/runs: on-disk format (schema note)

`eval-results/runs/<STORE>/<RUN_ID>/` holds one run:

- `run.json`: the run (one JSON object, 4–60 KB).
- `fixture.tgz`: the task's workspace as the run left it (with its `.git`), so checks and diffs can be recomputed offline.
- `judgments.jsonl` (bank1, cf3a, cf5 only): one judge verdict per line.

RUN_ID = `<task>__<endpoint>_<model with / → _>[_off]__t<trial>[__<degradation>]`, e.g.
`fix-calc__openrouter_anthropic_claude-haiku-4.5__t1`, `add-median__lmstudio_google_gemma-4-26b-a4b-qat__t1__stray-edit`.

## run.json top-level fields

| field | meaning |
|---|---|
| `id`, `task`, `trial`, `kind` (fix, edit, search, …), `agent` (general / explore), `card` {kind, importance, verify} | identity and the task card |
| `model` | `endpoint:model[#off]`, e.g. `openrouter:inclusionai/ling-3.0-flash`, `openrouter:deepseek/deepseek-v4-flash-0731#off` (#off = reasoning disabled), `lmstudio:…`, `bang:…` (LAN LM Studio), `google-gemini:…` |
| `prompt`, `report` | the task text sent; the agent's final report |
| `gold` {passed, score, notes[]} | the outcome against gold checks (the label every rate uses) |
| `checks` {steps, stop, toolCalls, toolErrors, repeatedCalls, filesChanged[], unmentionedChanges[], hardFailures[], citations, unresolvedCitations[], emptyReport, verifyCommand, verifyExitCode, maxSteps} | grounded checks at the run's end |
| `rechecked`, `recheckExit` | the re-run check (gold's command re-run) |
| `promptTokens`, `completionTokens`, `steps`, `toolCalls`, `stop`, `seconds`, `unpricedRequests` | run totals |
| `listPrice` | run's list price in USD (absent for local/unpriced runs) |
| `runRecord` | the full `AgentRunRecord`: `setup` {api, endpointID, host, model, maxSteps, maxOutputTokens, tools[], wallClock, promptCacheHour, webSearch}, `totals` {promptTokens, cacheReadTokens, cacheWriteTokens, completionTokens, reasoningTokens, requests, reconciledRequests, charged, listPrice{uncachedInput, cacheRead, cacheWrite5m, cacheWrite1h, output, reasoning, requests, searches, total}, modelSeconds, wallSeconds}, `outcome` {steps, stop, toolCalls by name, filesChanged, compactions, …}, `task` {text, hash, card}, `build` {gitCommit, executableHash, gitDirty}, `systemPromptHash`, `definitionHash`, `children` |
| `transcript[]` | every message: role, content, toolCalls, and `meta` {provider, requestedModel, reportedModel, requestIDs, usage{promptTokens, cacheReadTokens, cacheWriteTokens, completionTokens, cost}, usageRaw, finishReason, timeToFirstToken, duration} |
| `degradation`, `parent` (bank1, cf5) | a copy of a passing run made wrong on purpose: stray-edit, undo-all, undo-half, vanish (gold.passed = false) |
| `infra` (cf1: 451, cf2: 3) | an infrastructure failure (e.g. "Reasoning is mandatory for this endpoint and cannot be disabled"); excluded from rates |
| `commit`, `recordedAt`, `contextLimit` | provenance |

There is no `endpoint` or `cost` top-level field: the endpoint is the prefix of `model` (and `runRecord.setup.host/endpointID`); cost is `listPrice` and `runRecord.totals.charged` (OpenRouter's reconciled charge). The `cost report` uses `charged` where present, else list price.

## judgments.jsonl lines

`{"run": RUN_ID, "at": …, "outcome": {"judge": "endpoint:model[#off]", "path": "parent" | "grader", "verdict": 0–3 | absent, "checked", "issues"[], "note", "listPrice" (absent for local judges), "seconds", "judgment": {full RunJudgment incl. prompt, response, evidence, requestID}}}`. A verdict ≤ 1 = the judge says the run failed. Several lines per (run, judge, path) are possible (judge trials, `--rejudge-missing`); TriggerSim keeps the last with a verdict.

## Review-sim rows (eval-results/review-sim/bank1-rows.jsonl, not in the run store)

`{run, task, kind, model, group (real-fail | pass | stray-edit | undo-all | undo-half | vanish), goldPassed, reviewer, verdict (looks_right | has_problems | wrong | null), findings, problem, diffBytes, seconds, listPrice, charged, promptTokens, completionTokens, summary}`.
