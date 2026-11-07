import pickle, statistics as st, collections, sys
rows = pickle.load(open(sys.argv[1], "rb"))
real = [r for r in rows if not r["degradation"] and not r["infra"]]
def f(x, d=5): return "–" if x is None else f"{x:.{d}f}"
def table(rs, keyf, title):
    g = collections.defaultdict(list)
    for r in rs: g[keyf(r)].append(r)
    out = [f"### {title}\n", "| store | model | runs | pass rate | mean list $/run | median list $/run | priced runs | mean prompt tok | mean output tok | mean steps |",
           "|---|---|---|---|---|---|---|---|---|---|"]
    for k in sorted(g, key=lambda k: (k[0], -st.mean([1 if r['passed'] else 0 for r in g[k]]), k[1])):
        v = g[k]; n = len(v); p = sum(1 for r in v if r["passed"])
        prices = [r["listPrice"] for r in v if r["listPrice"] is not None]
        out.append(f"| {k[0]} | {k[1]} | {n} | {p}/{n} ({100*p/n:.1f}%) | {f(st.mean(prices)) if prices else '–'} | {f(st.median(prices)) if prices else '–'} | {len(prices)} | {st.mean(r['prompt'] or 0 for r in v):,.0f} | {st.mean(r['completion'] or 0 for r in v):,.0f} | {st.mean(r['steps'] or 0 for r in v):.1f} |")
    return "\n".join(out) + "\n"
md = ["# Per-model statistics computed directly from eval-results/runs (python3 -I, stdlib only)\n",
      "Real runs only: degraded copies (`degradation`) and infrastructure failures (`infra`) excluded. List cost = run.json `listPrice` (missing for local/unpriced runs). Pass = `gold.passed`. Prompt tokens are the run total over all requests (cached included).\n"]
bank = [r for r in real if r["store"] in ("cf2", "cf6", "bank1")]
hard = [r for r in real if r["store"] in ("cf3a", "cf3b")]
md.append("## Bank tier (cf2, cf6, bank1), per store and model\n")
md.append(table(bank, lambda r: (r["store"], r["model"]), "bank"))
md.append("## Hard tier (cf3a, cf3b), per store and model\n")
md.append(table(hard, lambda r: (r["store"], r["model"]), "hard"))
fr = [r for r in real if any(s in r["model"] for s in ("claude-opus", "claude-sonnet", "gemini-4-argon", "claude-haiku"))]
md.append("## Frontier and standard models (Opus, Sonnet, gemini-4-argon, Haiku), every store\n")
md.append(table(fr, lambda r: (r["store"], r["model"]), "frontier"))
# pooled across bank+hard, by model, for the shipped pool's models
md.append("## Pooled bank + hard tier (cf2+cf6+bank1+cf3a+cf3b), selected models\n")
sel = [r for r in bank + hard if any(s in r["model"] for s in ("ling-3.0-flash", "deepseek-v4-flash-0731", "claude-haiku-5.5", "mercury-2.5", "claude-opus-5.5", "claude-sonnet-5.5", "gemini-4-argon", "gemma-4-26b"))]
md.append(table(sel, lambda r: ("bank+hard", r["model"]), "pooled"))
open(sys.argv[2], "w").write("\n".join(md))
