Runs: 96 recorded, 0 degraded copies; 0 judgments.

### Subagent models (real runs, all trials)

| model | pass rate (95% CI) | mean s | mean steps | mean tokens in/out | list $ per run | $ per success |
|---|---|---|---|---|---|---|
| lmstudio:google/gemma-4-26b-a4b-qat | 93% (86–96%) 89/96 | 45 | 6.4 | 15036/1685 | – | – |

Passes by kind:

| model | edit | explain | fix | refactor | research | review | run | search | summarize | write-tests |
|---|---|---|---|---|---|---|---|---|---|---|
| lmstudio:google/gemma-4-26b-a4b-qat | 8/8 | 14/14 | 9/10 | 6/6 | 11/12 | 8/8 | 6/6 | 13/16 | 9/10 | 5/6 |

### Judges against gold

A verdict of 0–1 is "fail", 2–3 "pass". Failures are real failed runs and degraded copies.

All runs each judge rated:

| judge (path) | runs | no verdict | agreement | kappa | failures caught (95% CI) | passes failed (95% CI) | claimed unchecked | list $ |
|---|---|---|---|---|---|---|---|---|

### Grounded checks, and judges combined with them

|  | failures caught (95% CI) | passes failed (95% CI) |
|---|---|---|
| checks at the run's end | – | – |
| checks and the re-run check | – | – |

### Failures caught, by kind of failure

| failure | grounded |
|---|---|

### Judging its own model's runs, and others'

| judge (path) | own runs: agreement | own runs: failures caught | others' runs: agreement | others' runs: failures caught |
|---|---|---|---|---|
