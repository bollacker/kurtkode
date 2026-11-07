Runs: 96 recorded, 0 degraded copies; 0 judgments.

### Subagent models (real runs, all trials)

| model | pass rate (95% CI) | mean s | mean steps | mean tokens in/out | list $ per run | $ per success |
|---|---|---|---|---|---|---|
| lmstudio:google/gemma-4-26b-a4b-qat | 89% (81–93%) 85/96 | 46 | 6.7 | 20595/1655 | – | – |

Passes by kind:

| model | edit | explain | fix | refactor | research | review | run | search | summarize | write-tests |
|---|---|---|---|---|---|---|---|---|---|---|
| lmstudio:google/gemma-4-26b-a4b-qat | 6/8 | 13/14 | 10/10 | 6/6 | 9/12 | 7/8 | 6/6 | 14/16 | 10/10 | 4/6 |

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
