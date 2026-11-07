| parent | setup | survey (delegate) | log-sweep (delegate) | two-questions (delegate) | tiny-lookup (don't) | small-fix (don't) | mean $/run |
|---|---|---|---|---|---|---|---|
| claude-sonnet-5.5 | alone | 3/3 · $0.0724 · 38s | 3/3 · $0.0105 · 15s | 3/3 · $0.0088 · 14s | 3/3 · $0.0072 · 14s | 3/3 · $0.0129 · 17s | $0.0224 |
| claude-sonnet-5.5 | + claude-haiku-5.5 | 2/3 · $0.0814 · 54s · 4.0 sub | 3/3 · $0.0759 · 44s · 3.3 sub | 3/3 · $0.0353 · 33s · 2.0 sub | 3/3 · $0.0150 · 21s · 0.3 sub | 3/3 · $0.0278 · 34s · 0.7 sub | $0.0471 |
| claude-sonnet-5.5 | + ling-3.0-flash | 1/3 · $0.0542 · 49s · 3.3 sub | 3/3 · $0.0663 · 52s · 4.7 sub | 3/3 · $0.0303 · 32s · 2.0 sub | 3/3 · $0.0181 · 35s · 1.0 sub | 3/3 · $0.0252 · 32s · 0.7 sub | $0.0388 |
| gemini-4-argon | alone | 3/3 · $0.1446 · 95s | 3/3 · $0.2824 · 193s | 3/3 · $0.0078 · 33s | 3/3 · $0.0075 · 21s | 3/3 · $0.0180 · 31s | $0.0921 |
| gemini-4-argon | + claude-haiku-5.5 | 3/3 · $0.0841 · 96s · 3.3 sub | 3/3 · $0.0477 · 58s · 5.0 sub | 3/3 · $0.0284 · 45s · 2.0 sub | 3/3 · $0.0169 · 30s · 0.3 sub | 3/3 · $0.0435 · 76s · 2.0 sub | $0.0441 |
| gemini-4-argon | + ling-3.0-flash | 3/3 · $0.0428 · 74s · 4.0 sub | 3/3 · $0.0434 · 64s · 5.0 sub | 3/3 · $0.0266 · 51s · 2.0 sub | 3/3 · $0.0236 · 51s · 1.0 sub | 3/3 · $0.0333 · 59s · 1.3 sub | $0.0339 |
| gpt-5.6-sol | alone | 2/3 · $0.0582 · 27s | 2/3 · $0.1411 · 35s | 3/3 · $0.0164 · 15s | 3/3 · $0.0131 · 15s | 3/3 · $0.0144 · 19s | $0.0487 |
| gpt-5.6-sol | + claude-haiku-5.5 | 2/3 · $0.0912 · 61s · 4.3 sub | 3/3 · $0.0845 · 63s · 5.7 sub | 3/3 · $0.0405 · 37s · 2.0 sub | 3/3 · $0.0218 · 37s · 1.0 sub | 3/3 · $0.0605 · 61s · 2.0 sub | $0.0597 |
| gpt-5.6-sol | + ling-3.0-flash | 1/3 · $0.1018 · 63s · 4.3 sub | 3/3 · $0.0697 · 53s · 5.3 sub | 3/3 · $0.0539 · 42s · 3.0 sub | 3/3 · $0.0190 · 33s · 1.0 sub | 3/3 · $0.0455 · 63s · 2.0 sub | $0.0580 |
| ling-3.0-flash | alone | 1/3 · $0.0007 · 31s | 1/3 · $0.0001 · 15s | 3/3 · $0.0001 · 14s | 3/3 · $0.0000 · 13s | 3/3 · $0.0002 · 17s | $0.0002 |
| ling-3.0-flash | + ling-3.0-flash | 0/3 · $0.0025 · 68s · 1.0 sub | 1/3 · $0.0029 · 45s · 3.7 sub | 3/3 · $0.0006 · 28s · 1.3 sub | 3/3 · $0.0001 · 14s · 0.0 sub | 3/3 · $0.0003 · 17s · 0.0 sub | $0.0013 |

Failures:

- claude-sonnet-5.5 + claude-haiku-5.5, survey: 5/5 right; wrong: ["2026-01-24.md", "2026-02-24.md", "2026-03-17.md"]
- claude-sonnet-5.5 + ling-3.0-flash, survey: 5/5 right; wrong: ["2026-01-24.md", "2026-02-24.md"]
- claude-sonnet-5.5 + ling-3.0-flash, survey: 5/5 right; wrong: ["2026-01-24.md", "2026-02-24.md"]
- gpt-5.6-sol + claude-haiku-5.5, survey: 5/5 right; wrong: ["2026-03-17.md"]
- gpt-5.6-sol + ling-3.0-flash, survey: 5/5 right; wrong: ["2026-03-17.md"]
- gpt-5.6-sol + ling-3.0-flash, survey: 5/5 right; wrong: ["2026-03-17.md"]
- gpt-5.6-sol alone, log-sweep: 2/3 counts right; subagent runs: 0
- gpt-5.6-sol alone, survey: 4/5 right; none wrong
- ling-3.0-flash + ling-3.0-flash, log-sweep: 2/3 counts right; subagent runs: 5
- ling-3.0-flash + ling-3.0-flash, log-sweep: 2/3 counts right; subagent runs: 5
- ling-3.0-flash + ling-3.0-flash, survey: 5/5 right; wrong: ["2026-01-24.md", "2026-02-24.md"]
- ling-3.0-flash + ling-3.0-flash, survey: 0/5 right; wrong: ["2026-01-24.md", "2026-02-24.md"]
- ling-3.0-flash + ling-3.0-flash, survey: 5/5 right; wrong: ["2026-04-03.md", "2026-04-10.md", "2026-04-24.md"]
- ling-3.0-flash alone, log-sweep: 2/3 counts right; subagent runs: 0
- ling-3.0-flash alone, log-sweep: 2/3 counts right; subagent runs: 0
- ling-3.0-flash alone, survey: 2/5 right; wrong: ["2026-02-24.md"]
- ling-3.0-flash alone, survey: 2/5 right; wrong: ["2026-01-24.md", "2026-02-24.md"]
