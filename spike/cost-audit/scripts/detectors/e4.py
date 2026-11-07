# E4: task-level failure structure; clustering vs independent-failure model
import sys, os, json, collections, random, math
D = sys.argv[1]; OUT = sys.argv[2]
random.seed(7)
md = []; p = lambda s="": md.append(s)
HK = "openrouter:anthropic/claude-haiku-5.5"; LING = "openrouter:inclusionai/ling-3.0-flash"; MER = "openrouter:inception/mercury-2.5"
p("## E4. Task-level failure structure\n")
p("Clustering test: given a model's k failures over its runs (n_t trials of task t), how many distinct tasks would hold them if failures were independent of the task? `binomial` = Σ_t 1−(1−p)^{n_t} with p = k/N; `random placement` = Monte Carlo (20,000 draws) of k failures placed uniformly among the model's N runs, with P(distinct ≤ observed) as a one-sided p-value for clustering.\n")
for store in ("cf6", "cf3a"):
    runs = collections.defaultdict(dict)
    for l in open(os.path.join(D, store + ".jsonl")):
        r = json.loads(l); runs[r["model"]][(r["task"], r["trial"])] = r["passed"]
    models = [m for m in runs if len(runs[m]) >= 140]
    models.sort(key=lambda m: -sum(not v for v in runs[m].values()))
    tasks = sorted({k[0] for m in models for k in runs[m]})
    p(f"### {store}: {len(tasks)} tasks\n")
    p("| model | runs | failures | tasks with ≥1 failure (observed) | expected, binomial | expected, random placement | P(distinct ≤ observed) | max failures on one task |")
    p("|---|---|---|---|---|---|---|---|")
    pooled = collections.Counter()
    for m in models:
        nt = collections.Counter(k[0] for k in runs[m]); ft = collections.Counter(k[0] for k, v in runs[m].items() if not v)
        pooled.update(ft)
        k = sum(ft.values()); N = sum(nt.values())
        if k == 0: continue
        obs = len(ft); pr = k / N
        eb = sum(1 - (1 - pr) ** n for n in nt.values())
        ids = [t for t, n in nt.items() for _ in range(n)]
        sims = []
        for _ in range(20000):
            sims.append(len(set(random.sample(ids, k))))
        er = sum(sims) / len(sims); pv = sum(1 for s in sims if s <= obs) / len(sims)
        p(f"| {m.split(':',1)[1]} | {N} | {k} | {obs} | {eb:.2f} | {er:.2f} | {pv:.4f} | {max(ft.values())} |")
    p()
    # per-task failure table (tasks with any failure among the models)
    ft_tasks = [t for t in tasks if pooled[t] > 0]
    show = models if store == "cf6" else models[:12]
    p(f"Failures per task (out of 10 trials; tasks with ≥1 failure for any listed model; {len(ft_tasks)} of {len(tasks)} tasks):\n")
    p("| task | " + " | ".join(m.split('/')[-1] for m in show) + " | total |"); p("|---|" + "---|" * (len(show) + 1))
    for t in sorted(ft_tasks, key=lambda t: -pooled[t]):
        cells = [str(sum(1 for (tt, tr), v in runs[m].items() if tt == t and not v)) for m in show]
        p(f"| {t} | " + " | ".join(c if c != "0" else "·" for c in cells) + f" | {pooled[t]} |")
    p()
    # escalation-relevant lists
    for cheap in ([LING] if store == "cf6" else [MER, LING]):
        cf = collections.Counter(k[0] for k, v in runs[cheap].items() if not v)
        hk = runs[HK]
        p(f"{cheap.split('/')[-1]} failures vs Haiku on the same tasks ({store}):\n")
        p("| task | " + cheap.split('/')[-1] + " failures | Haiku failures (of 10) | Haiku passes the same trial on each failing trial? |"); p("|---|---|---|---|")
        rec = 0
        for t, n in sorted(cf.items(), key=lambda x: -x[1]):
            hf = sum(1 for (tt, tr), v in hk.items() if tt == t and not v)
            same = [hk.get(k) for k, v in runs[cheap].items() if k[0] == t and not v]
            rec += sum(1 for s in same if s)
            p(f"| {t} | {n} | {hf} | {sum(1 for s in same if s)}/{len(same)} |")
        N = len(runs[cheap]); base = sum(runs[cheap].values())
        p(f"\nOracle escalation ceiling (escalate exactly the failing runs to Haiku's run of the same task/trial): {cheap.split('/')[-1]} {100*base/N:.2f}% → {100*(base+rec)/N:.2f}% ({rec} of {N-base} failures recoverable). Tasks where {cheap.split('/')[-1]} fails and Haiku passes all 10: " + ", ".join(t for t in cf if all(v for (tt, tr), v in hk.items() if tt == t)) + ".\n")
    hf = collections.Counter(k[0] for k, v in runs[HK].items() if not v)
    p(f"Haiku failures in {store}: " + ", ".join(f"{t} ({n}/10)" for t, n in hf.items()) + "\n")
open(OUT, "w").write("\n".join(md))
