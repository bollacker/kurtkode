# Judge calibration recomputed from judgments.jsonl (python3 -I)

Verdict ≤ 1 = the judge flags the run as failed. Per run, the last judgment with a verdict for each (path, judge) counts (as in TriggerSim.signals). Recall = flagged gold failures / gold failures the judge gave a verdict on. Precision = gold failures among flagged. False alarms = flagged gold passes / gold passes judged. Kappa = Cohen's kappa of (verdict ≥ 2) against gold pass. Cost = mean `listPrice` over all of that judge's judgment entries (verdict or not); local judges have none.

## bank1, real runs only: 612 runs, 42 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 196 | 0 | 57% (8/14) | 24% (8/33) | 14% (25/182) | 0.27 | – | 197 |
| grader | gemini-3.8-flash | 204 | 0 | 36% (5/14) | 56% (5/9) | 2% (4/190) | 0.40 | $0.00232 | 204 |
| grader | gemini-4-argon | 204 | 0 | 36% (5/14) | 71% (5/7) | 1% (2/190) | 0.45 | $0.00320 | 204 |
| grader | gemma-4-26b-a4b-qat | 155 | 3 | 29% (4/14) | 57% (4/7) | 2% (3/141) | 0.34 | – | 178 |
| parent | qwen3.5-9b | 192 | 4 | 31% (4/13) | 40% (4/10) | 3% (6/179) | 0.31 | – | 211 |
| parent | gemini-3.8-flash | 203 | 1 | 57% (8/14) | 100% (8/8) | 0% (0/189) | 0.71 | $0.00964 | 243 |
| parent | gemini-4-argon | 204 | 0 | 71% (10/14) | 100% (10/10) | 0% (0/190) | 0.82 | $0.01461 | 207 |
| parent | gemma-4-26b-a4b-qat | 125 | 33 | 20% (2/10) | 67% (2/3) | 1% (1/115) | 0.28 | – | 216 |

## bank1, real + degraded copies: 1071 runs, 501 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 367 | 0 | 50% (92/185) | 79% (92/117) | 14% (25/182) | 0.36 | – | 369 |
| grader | gemini-3.8-flash | 663 | 0 | 44% (209/473) | 98% (209/213) | 2% (4/190) | 0.30 | $0.00263 | 663 |
| grader | gemini-4-argon | 663 | 0 | 43% (203/473) | 99% (203/205) | 1% (2/190) | 0.29 | $0.00322 | 663 |
| grader | gemma-4-26b-a4b-qat | 298 | 3 | 40% (63/157) | 95% (63/66) | 2% (3/141) | 0.37 | – | 342 |
| parent | qwen3.5-9b | 350 | 17 | 43% (73/171) | 92% (73/79) | 3% (6/179) | 0.40 | – | 420 |
| parent | gemini-3.8-flash | 657 | 6 | 55% (256/468) | 100% (256/256) | 0% (0/189) | 0.41 | $0.01006 | 796 |
| parent | gemini-4-argon | 660 | 3 | 56% (262/470) | 100% (262/262) | 0% (0/190) | 0.42 | $0.01525 | 675 |
| parent | gemma-4-26b-a4b-qat | 245 | 56 | 46% (60/130) | 98% (60/61) | 1% (1/115) | 0.44 | – | 416 |

## cf5, real runs only: 123 runs, 9 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 123 | 0 | 56% (5/9) | 31% (5/16) | 10% (11/114) | 0.34 | – | 124 |
| grader | gemini-3.8-flash | 123 | 0 | 22% (2/9) | 67% (2/3) | 1% (1/114) | 0.31 | $0.00212 | 123 |
| grader | gemini-4-argon | 123 | 0 | 33% (3/9) | 60% (3/5) | 2% (2/114) | 0.40 | $0.00316 | 123 |
| grader | gemma-4-26b-a4b-qat | 121 | 2 | 11% (1/9) | 50% (1/2) | 1% (1/112) | 0.16 | – | 134 |
| parent | qwen3.5-9b | 123 | 0 | 22% (2/9) | 29% (2/7) | 4% (5/114) | 0.20 | – | 131 |
| parent | gemini-3.8-flash | 123 | 0 | 44% (4/9) | 100% (4/4) | 0% (0/114) | 0.60 | $0.00922 | 140 |
| parent | gemini-4-argon | 123 | 0 | 78% (7/9) | 100% (7/7) | 0% (0/114) | 0.87 | $0.01372 | 124 |
| parent | gemma-4-26b-a4b-qat | 123 | 0 | 22% (2/9) | 67% (2/3) | 1% (1/114) | 0.31 | – | 147 |
| parent | claude-haiku-5.5 | 123 | 0 | 67% (6/9) | 75% (6/8) | 2% (2/114) | 0.68 | $0.00114 | 123 |
| parent | deepseek-v4-flash | 119 | 4 | 33% (3/9) | 100% (3/3) | 0% (0/110) | 0.48 | $0.00071 | 123 |
| parent | deepseek-v4-flash-0731 | 120 | 3 | 44% (4/9) | 100% (4/4) | 0% (0/111) | 0.60 | $0.00042 | 123 |
| parent | mercury-3 | 122 | 1 | 67% (6/9) | 100% (6/6) | 0% (0/113) | 0.79 | $0.00047 | 123 |
| parent | ling-3.0-flash | 121 | 2 | 22% (2/9) | 100% (2/2) | 0% (0/112) | 0.35 | $0.00015 | 123 |
| parent | ling-3.1-flash | 120 | 3 | 78% (7/9) | 100% (7/7) | 0% (0/111) | 0.87 | $0.00059 | 123 |
| parent | gpt-6-luna | 123 | 0 | 33% (3/9) | 43% (3/7) | 4% (4/114) | 0.33 | $0.00053 | 123 |
| parent | laguna-s-2.1 | 119 | 4 | 33% (3/9) | 100% (3/3) | 0% (0/110) | 0.48 | $0.00052 | 123 |
| parent | qwen3.7-flash | 121 | 2 | 56% (5/9) | 100% (5/5) | 0% (0/112) | 0.70 | $0.00025 | 123 |
| parent | glm-4.7-flash | 114 | 9 | 22% (2/9) | 67% (2/3) | 1% (1/105) | 0.31 | $0.00067 | 123 |

## cf5, real + degraded copies: 236 runs, 122 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 236 | 0 | 44% (54/122) | 83% (54/65) | 10% (11/114) | 0.34 | – | 238 |
| grader | gemini-3.8-flash | 236 | 0 | 38% (46/122) | 98% (46/47) | 1% (1/114) | 0.36 | $0.00237 | 236 |
| grader | gemini-4-argon | 236 | 0 | 38% (46/122) | 96% (46/48) | 2% (2/114) | 0.35 | $0.00322 | 236 |
| grader | gemma-4-26b-a4b-qat | 234 | 2 | 37% (45/122) | 98% (45/46) | 1% (1/112) | 0.35 | – | 262 |
| parent | qwen3.5-9b | 236 | 0 | 43% (52/122) | 91% (52/57) | 4% (5/114) | 0.38 | – | 268 |
| parent | gemini-3.8-flash | 236 | 0 | 47% (57/122) | 100% (57/57) | 0% (0/114) | 0.46 | $0.00904 | 268 |
| parent | gemini-4-argon | 236 | 0 | 51% (62/122) | 100% (62/62) | 0% (0/114) | 0.50 | $0.01391 | 241 |
| parent | gemma-4-26b-a4b-qat | 236 | 0 | 45% (55/122) | 98% (55/56) | 1% (1/114) | 0.43 | – | 291 |
| parent | claude-haiku-5.5 | 236 | 0 | 49% (60/122) | 97% (60/62) | 2% (2/114) | 0.47 | $0.00112 | 236 |
| parent | deepseek-v4-flash | 224 | 12 | 45% (51/114) | 100% (51/51) | 0% (0/110) | 0.44 | $0.00073 | 236 |
| parent | deepseek-v4-flash-0731 | 233 | 3 | 43% (53/122) | 100% (53/53) | 0% (0/111) | 0.42 | $0.00043 | 236 |
| parent | mercury-3 | 233 | 3 | 45% (54/120) | 100% (54/54) | 0% (0/113) | 0.44 | $0.00050 | 236 |
| parent | ling-3.0-flash | 229 | 7 | 43% (50/117) | 100% (50/50) | 0% (0/112) | 0.42 | $0.00016 | 236 |
| parent | ling-3.1-flash | 231 | 5 | 50% (60/120) | 100% (60/60) | 0% (0/111) | 0.49 | $0.00058 | 236 |
| parent | gpt-6-luna | 236 | 0 | 46% (56/122) | 93% (56/60) | 4% (4/114) | 0.42 | $0.00052 | 236 |
| parent | laguna-s-2.1 | 224 | 12 | 40% (46/114) | 100% (46/46) | 0% (0/110) | 0.40 | $0.00052 | 236 |
| parent | qwen3.7-flash | 229 | 7 | 45% (53/117) | 100% (53/53) | 0% (0/112) | 0.45 | $0.00027 | 236 |
| parent | glm-4.7-flash | 217 | 19 | 46% (52/112) | 98% (52/53) | 1% (1/105) | 0.45 | $0.00069 | 236 |

## cf5, stage-5 subset (real + degraded, minus stray-edit copies of explore tasks): 204 runs, 90 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3.5-9b | 204 | 0 | 57% (51/90) | 82% (51/62) | 10% (11/114) | 0.49 | – | 205 |
| grader | gemini-3.8-flash | 204 | 0 | 51% (46/90) | 98% (46/47) | 1% (1/114) | 0.53 | $0.00241 | 204 |
| grader | gemini-4-argon | 204 | 0 | 51% (46/90) | 96% (46/48) | 2% (2/114) | 0.52 | $0.00321 | 204 |
| grader | gemma-4-26b-a4b-qat | 202 | 2 | 49% (44/90) | 98% (44/45) | 1% (1/112) | 0.50 | – | 227 |
| parent | qwen3.5-9b | 204 | 0 | 58% (52/90) | 91% (52/57) | 4% (5/114) | 0.56 | – | 234 |
| parent | gemini-3.8-flash | 204 | 0 | 63% (57/90) | 100% (57/57) | 0% (0/114) | 0.66 | $0.00918 | 232 |
| parent | gemini-4-argon | 204 | 0 | 69% (62/90) | 100% (62/62) | 0% (0/114) | 0.71 | $0.01408 | 208 |
| parent | gemma-4-26b-a4b-qat | 204 | 0 | 61% (55/90) | 98% (55/56) | 1% (1/114) | 0.63 | – | 253 |
| parent | claude-haiku-5.5 | 204 | 0 | 67% (60/90) | 97% (60/62) | 2% (2/114) | 0.67 | $0.00112 | 204 |
| parent | deepseek-v4-flash | 193 | 11 | 61% (51/83) | 100% (51/51) | 0% (0/110) | 0.64 | $0.00075 | 204 |
| parent | deepseek-v4-flash-0731 | 201 | 3 | 59% (53/90) | 100% (53/53) | 0% (0/111) | 0.61 | $0.00044 | 204 |
| parent | mercury-3 | 202 | 2 | 61% (54/89) | 100% (54/54) | 0% (0/113) | 0.63 | $0.00051 | 204 |
| parent | ling-3.0-flash | 199 | 5 | 57% (50/87) | 100% (50/50) | 0% (0/112) | 0.60 | $0.00017 | 204 |
| parent | ling-3.1-flash | 201 | 3 | 67% (60/90) | 100% (60/60) | 0% (0/111) | 0.69 | $0.00059 | 204 |
| parent | gpt-6-luna | 204 | 0 | 61% (55/90) | 93% (55/59) | 4% (4/114) | 0.60 | $0.00051 | 204 |
| parent | laguna-s-2.1 | 193 | 11 | 55% (46/83) | 100% (46/46) | 0% (0/110) | 0.59 | $0.00053 | 204 |
| parent | qwen3.7-flash | 197 | 7 | 62% (53/85) | 100% (53/53) | 0% (0/112) | 0.65 | $0.00027 | 204 |
| parent | glm-4.7-flash | 190 | 14 | 60% (51/85) | 98% (51/52) | 1% (1/105) | 0.61 | $0.00070 | 204 |

## cf3a (mercury-2.5 runs), real runs only: 140 runs, 12 gold failures

| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |
|---|---|---|---|---|---|---|---|---|---|
| grader | qwen3-coder-30b | 89 | 0 | 27% (3/11) | 21% (3/14) | 14% (11/78) | 0.12 | – | 89 |
| grader | claude-haiku-5.5 | 140 | 0 | 58% (7/12) | 24% (7/29) | 17% (22/128) | 0.25 | $0.00048 | 140 |
| grader | deepseek-v4-flash-0731#off | 58 | 82 | 25% (2/8) | 22% (2/9) | 14% (7/50) | 0.10 | $0.00012 | 140 |
| parent | qwen3-coder-30b | 86 | 2 | 9% (1/11) | 100% (1/1) | 0% (0/75) | 0.15 | – | 88 |
| parent | claude-haiku-5.5 | 140 | 0 | 25% (3/12) | 33% (3/9) | 5% (6/128) | 0.23 | $0.00146 | 140 |
| parent | deepseek-v4-flash-0731#off | 137 | 3 | 44% (4/9) | 67% (4/6) | 2% (2/128) | 0.51 | $0.00046 | 140 |
