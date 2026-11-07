# E3: where the money goes inside a run; cache shares; extrapolation; seconds per run
import sys, os, json, statistics as st, collections
D = sys.argv[1]; OUT = sys.argv[2]
md = []; p = lambda s="": md.append(s)
def med(v): return st.median(v) if v else float("nan")
def mean(v): return st.mean(v) if v else float("nan")
SEL = [("cf6", "inclusionai/ling-3.0-flash"), ("cf6", "deepseek/deepseek-v4-flash-0731#off"), ("cf6", "anthropic/claude-haiku-5.5"),
       ("cf3a", "inclusionai/ling-3.0-flash"), ("cf3a", "deepseek/deepseek-v4-flash-0731#off"), ("cf3a", "anthropic/claude-haiku-5.5"),
       ("cf3a", "inception/mercury-2.5"), ("cf3b", "anthropic/claude-opus-5.5"), ("cf3b", "anthropic/claude-sonnet-5.5"),
       ("cf3b", "google/gemini-4-argon"), ("bank1", "gemini-4-argon")]
def load(store):
    g = collections.defaultdict(list)
    for l in open(os.path.join(D, store + ".jsonl")):
        r = json.loads(l); r.pop("report", None); g[r["model"]].append(r)
    return g
stores = {s: load(s) for s in ("cf6", "cf3a", "cf3b", "bank1")}
def pick(store, frag):
    ms = [m for m in stores[store] if m.split(":", 1)[1] == frag or m.endswith(":" + frag) or m.split(":", 1)[1].endswith(frag)]
    ms = [m for m in ms if ("#off" in m) == ("#off" in frag)]
    return ms[0]
p("## E3. Where the money goes inside a run\n")
p("Per run, from `runRecord.totals.listPrice` (component split) and the transcript's per-request `meta.usage` (request 0 = the first request, whose prompt is the fixed overhead: system prompt + tool schemas + skills listing + task). Shares are means of per-run shares (each run weighted equally). (a) cuts across (b)–(e); (b)+(c)+(d)+(e) = 100% (the stored `reasoning` component is a part of `output`, not added to it). The cf6 deepseek list price is inflated ~6× (its stored unit prices are not the provider's), so its shares are indicative only; charged is shown for reference.\n")
p("| store | model | runs | mean steps (requests) | mean list $/run | mean charged $/run | (a) first request | (b) cache reads | (c) uncached prompt | (d) cache writes | (e) output (incl. reasoning) | first-request prompt tok, median (explore / general agent) | of which cached from earlier runs (median) | first-request prompt / all prompt tokens | cached / all prompt tokens |")
p("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
models = {}
for store, frag in SEL:
    m = pick(store, frag); runs = [r for r in stores[store][m] if r["reqs"] and r["lp"]]
    models[(store, frag)] = (m, runs)
    sh = collections.defaultdict(list)
    for r in runs:
        lp = r["lp"]; tot = lp["total"] or 0
        if tot <= 0: continue
        costs = [q[5] for q in r["reqs"]]
        if all(c is not None for c in costs) and sum(costs) > 0: sh["a"].append(costs[0] / sum(costs))
        sh["b"].append(lp["cacheRead"] / tot); sh["c"].append(lp["uncachedInput"] / tot)
        sh["d"].append((lp["cacheWrite5m"] + lp["cacheWrite1h"]) / tot); sh["e"].append(lp["output"] / tot)
        sp = sum(q[0] for q in r["reqs"]); sh["fp"].append(r["reqs"][0][0] / sp if sp else 0); sh["cs"].append(sum(q[1] for q in r["reqs"]) / sp if sp else 0)
    ch = [r["charged"] for r in runs if r["charged"] is not None]
    p(f"| {store} | {frag} | {len(runs)} | {mean([len(r['reqs']) for r in runs]):.1f} | ${mean([r['listPrice'] or r['lp']['total'] for r in runs]):.5f} | {('$%.5f' % mean(ch)) if ch else '–'} | "
      + " | ".join(f"{100*mean(sh[k]):.1f}%" for k in "abcde")
      + f" | {med([r['reqs'][0][0] for r in runs]):,.0f} ({med([r['reqs'][0][0] for r in runs if r.get('agent') == 'explore']):,.0f} / {med([r['reqs'][0][0] for r in runs if r.get('agent') != 'explore']):,.0f}) | {med([r['reqs'][0][1] for r in runs]):,.0f} | {100*mean(sh['fp']):.1f}% | {100*mean(sh['cs']):.1f}% |")
p()
# cache-read share per request index
p("### Cache-read share of each request's prompt, by request index (mean over runs that reached that index; n in parentheses)\n")
idxs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20]
p("| store | model | " + " | ".join(f"req {i}" for i in idxs) + " |"); p("|---|---|" + "---|" * len(idxs))
for (store, frag), (m, runs) in models.items():
    cells = []
    for i in idxs:
        v = [r["reqs"][i][1] / r["reqs"][i][0] for r in runs if len(r["reqs"]) > i and r["reqs"][i][0]]
        cells.append(f"{100*mean(v):.0f}% ({len(v)})" if v else "–")
    p(f"| {store} | {frag} | " + " | ".join(cells) + " |")
p()
# cache share as a function of steps
bins = [(1, 2), (3, 3), (4, 4), (5, 5), (6, 7), (8, 10), (11, 15), (16, 99)]
p("### Run-level cached share of prompt tokens (and cache-read share of list cost) by number of requests in the run\n")
p("| store | model | " + " | ".join(f"{a}–{b} req" if a != b else f"{a} req" for a, b in bins) + " |"); p("|---|---|" + "---|" * len(bins))
for (store, frag), (m, runs) in models.items():
    cells = []
    for a, b in bins:
        v = [r for r in runs if a <= len(r["reqs"]) <= b]
        if not v: cells.append("–"); continue
        tok = mean([sum(q[1] for q in r["reqs"]) / max(1, sum(q[0] for q in r["reqs"])) for r in v])
        cost = mean([r["lp"]["cacheRead"] / r["lp"]["total"] for r in v if r["lp"]["total"]])
        cells.append(f"{100*tok:.0f}% / {100*cost:.0f}% (n={len(v)})")
    p(f"| {store} | {frag} | " + " | ".join(cells) + " |")
p()
# extrapolation
p("### Extrapolation: an ideally cached run of N requests\n")
p("Model per store/model: request i's prompt = P0 + g·i, with P0 = median first-request prompt and g = median growth per request ((last − first prompt)/(requests − 1), runs with ≥3 requests); every later request reads the whole previous prompt from the cache (cached_i = prompt_{i−1}); request 0 reads the median cross-run cached prefix h0; the new suffix is uncached (or a cache write at the write rate, for models that write, i.e. Anthropic); output per request = median completion tokens per request. Unit prices = medians of the per-run component price ÷ tokens. 'Observed' = mean measured cached share for runs with that many requests (±1), where any exist. Shares in the cost columns are of the extrapolated list cost.\n")
p("| store | model | P0 | g (tok/request) | out/request | h0 | caching? | N | ideal cached share of prompt tokens | observed (runs with N±1 requests) | ideal $/run | same N, no cache $/run | first-request share of $ | cache-read share of $ | uncached+write share of $ | output share of $ |")
p("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for (store, frag), (m, runs) in models.items():
    P0 = med([r["reqs"][0][0] for r in runs]); h0 = med([r["reqs"][0][1] for r in runs])
    g = med([(r["reqs"][-1][0] - r["reqs"][0][0]) / (len(r["reqs"]) - 1) for r in runs if len(r["reqs"]) >= 3])
    outq = med([q[3] for r in runs for q in r["reqs"]])
    caches = any(r["cacheRead"] for r in runs); writes = any(r["cacheWrite"] for r in runs)
    def unit(num, den):
        v = [num(r) / den(r) for r in runs if den(r) and den(r) > 0]
        return med(v) if v else 0
    u = unit(lambda r: r["lp"]["uncachedInput"], lambda r: r["promptTokens"] - (r["cacheRead"] or 0) - (r["cacheWrite"] or 0))
    c = unit(lambda r: r["lp"]["cacheRead"], lambda r: r["cacheRead"] or 0)
    w = unit(lambda r: r["lp"]["cacheWrite5m"] + r["lp"]["cacheWrite1h"], lambda r: r["cacheWrite"] or 0)
    o = unit(lambda r: r["lp"]["output"], lambda r: r["completion"] or 0)
    obs_mean_n = mean([len(r["reqs"]) for r in runs])
    for N in (round(obs_mean_n), 10, 20, 40):
        prompts = [P0 + g * i for i in range(N)]
        cached = [(h0 if i == 0 else prompts[i - 1]) if caches else 0 for i in range(N)]
        new = [prompts[i] - cached[i] for i in range(N)]
        cost_req = [cached[i] * c + new[i] * (w if writes else u) + outq * o for i in range(N)]
        tot = sum(cost_req)
        nocache = sum(prompts) * u + N * outq * o
        obs = [sum(q[1] for q in r["reqs"]) / sum(q[0] for q in r["reqs"]) for r in runs if abs(len(r["reqs"]) - N) <= 1]
        p(f"| {store} | {frag} | {P0:,.0f} | {g:,.0f} | {outq:.0f} | {h0:,.0f} | {'read+write' if writes else ('read' if caches else 'none')} | {N}{' (obs. mean)' if N == round(obs_mean_n) else ''} | {100*sum(cached)/sum(prompts):.0f}% | {('%.0f%% (n=%d)' % (100*mean(obs), len(obs))) if obs else '–'} | ${tot:.5f} | ${nocache:.5f} | {100*cost_req[0]/tot:.0f}% | {100*sum(cached)*c/tot:.0f}% | {100*sum(new)*(w if writes else u)/tot:.0f}% | {100*N*outq*o/tot:.0f}% |")
    p(f"| | unit prices $/M tok: uncached {u*1e6:.3f}, cache read {c*1e6:.4f}, write {w*1e6:.3f}, output {o*1e6:.3f}; observed mean list $/run {mean([r['lp']['total'] for r in runs]):.5f} at mean {obs_mean_n:.1f} requests | | | | | | | | | | | | | | |")
p()
# seconds
p("### Wall-clock seconds per run (users' waiting time)\n")
p("`seconds` = run.json wall time; model s = `runRecord.totals.modelSeconds` (time inside model requests). Different stores hold different task sets: cf6 = 48 bank tasks, bank1 = 34 bank tasks (the only store with local models; compare within it), cf3a/cf3b = the 14 hard tasks.\n")
p("| store | model | runs | pass | mean s | median s | p90 s | mean model s | mean steps | s per step (mean) |")
p("|---|---|---|---|---|---|---|---|---|---|")
want = [("cf6", "ling-3.0-flash"), ("cf6", "deepseek-v4-flash-0731#off"), ("cf6", "claude-haiku-5.5"),
        ("cf3a", "ling-3.0-flash"), ("cf3a", "deepseek-v4-flash-0731#off"), ("cf3a", "claude-haiku-5.5"), ("cf3a", "mercury-2.5"),
        ("cf3b", "claude-opus-5.5"), ("cf3b", "claude-sonnet-5.5"), ("cf3b", "gemini-4-argon"), ("cf3b", "gpt-5.6-sol"), ("cf3b", "kimi-k3.1-pro"),
        ("bank1", "gemini-4-argon"), ("bank1", "gemini-3.6-flash"), ("bank1", "gemini-3.8-flash"),
        ("bank1", "gemma-4-26b-a4b-qat"), ("bank1", "qwen3.5-9b"), ("bank1", "gemma-4-e4b-it")]
for store, frag in want:
    ms = [m for m in stores[store] if m.endswith(frag) or m.endswith(frag.replace("#off", "")) and "#off" not in m and "#off" not in frag]
    ms = [m for m in ms if m.endswith(frag)]
    for m in ms:
        v = stores[store][m]; s = sorted(r["seconds"] for r in v if r["seconds"] is not None)
        p(f"| {store} | {m} | {len(v)} | {100*sum(r['passed'] for r in v)/len(v):.1f}% | {mean(s):.1f} | {med(s):.1f} | {s[int(0.9*(len(s)-1))]:.1f} | {mean([r['modelSeconds'] for r in v if r['modelSeconds']]):.1f} | {mean([r['steps'] or 0 for r in v]):.1f} | {mean([r['seconds']/r['steps'] for r in v if r['steps']]):.2f} |")
open(OUT, "w").write("\n".join(md))
