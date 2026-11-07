# Baselines for E1/E2 economics: escalate-if-empty-report (free) and oracle escalation
import sys, os, json, statistics as st
D = sys.argv[1]
HK = "openrouter:anthropic/claude-haiku-5.5"
out = ["### Baselines for the cascade economics\n", "`empty` = escalate to Haiku only when the cheap run's report is empty (free; the existing emptyReport check). `oracle` = escalate exactly the gold failures (upper bound for any detector). Final answer on escalation = Haiku's run of the same task/trial.\n",
       "| store | cheap model | $/run cheap | Haiku $/run | policy | fire rate | recall | precision | cascade $/run | cascade pass | always-cheap pass | always-Haiku pass |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
for store, cheap, cost in (("cf6", "openrouter:inclusionai/ling-3.0-flash", None), ("cf6", "openrouter:deepseek/deepseek-v4-flash-0731#off", 0.00045),
                           ("cf3a", "openrouter:inception/mercury-2.5", None), ("cf3a", "openrouter:inclusionai/ling-3.0-flash", None)):
    runs = {}
    for l in open(os.path.join(D, store + ".jsonl")):
        r = json.loads(l)
        if r["model"] in (cheap, HK): runs[(r["model"], r["task"], r["trial"])] = r
    keys = [(t, tr) for (m, t, tr) in runs if m == cheap and (HK, t, tr) in runs]
    c = cost or st.mean(runs[(cheap,) + k]["listPrice"] for k in keys)
    h = st.mean(r["listPrice"] for kk, r in runs.items() if kk[0] == HK)
    pa = sum(runs[(cheap,) + k]["passed"] for k in keys) / len(keys); ph = sum(runs[(HK,) + k]["passed"] for k in keys) / len(keys)
    nf = sum(1 for k in keys if not runs[(cheap,) + k]["passed"])
    for name, fire in (("empty", lambda k: not runs[(cheap,) + k]["report"].strip()), ("oracle", lambda k: not runs[(cheap,) + k]["passed"])):
        F = [k for k in keys if fire(k)]; tp = sum(1 for k in F if not runs[(cheap,) + k]["passed"])
        ok = sum(runs[(HK,) + k]["passed"] if fire(k) else runs[(cheap,) + k]["passed"] for k in keys) / len(keys)
        out.append(f"| {store} | {cheap.split('/')[-1]} | ${c:.5f} | ${h:.5f} | {name} | {100*len(F)/len(keys):.1f}% | {tp}/{nf} | {('%.0f%%' % (100*tp/len(F))) if F else '–'} | ${c + h*len(F)/len(keys):.5f} | {100*ok:.2f}% | {100*pa:.2f}% | {100*ph:.2f}% |")
print("\n".join(out))
open(sys.argv[2], "w").write("\n".join(out) + "\n")
