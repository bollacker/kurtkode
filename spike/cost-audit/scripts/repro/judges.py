import pickle, collections, sys, statistics as st
rows = pickle.load(open(sys.argv[1], "rb"))
def short(j): return j.split(":")[-1].split("/")[-1]
def kappa(tp, fp, fn, tn):
    n = tp+fp+fn+tn
    if n == 0: return None
    po = (tp+tn)/n
    pe = ((tp+fp)*(tp+fn) + (fn+tn)*(fp+tn))/(n*n)
    return None if pe == 1 else (po-pe)/(1-pe)
def pct(a, b): return "–" if b == 0 else f"{100*a/b:.0f}% ({a}/{b})"
out = ["# Judge calibration recomputed from judgments.jsonl (python3 -I)\n",
       "Verdict ≤ 1 = the judge flags the run as failed. Per run, the last judgment with a verdict for each (path, judge) counts (as in TriggerSim.signals). Recall = flagged gold failures / gold failures the judge gave a verdict on. Precision = gold failures among flagged. False alarms = flagged gold passes / gold passes judged. Kappa = Cohen's kappa of (verdict ≥ 2) against gold pass. Cost = mean `listPrice` over all of that judge's judgment entries (verdict or not); local judges have none.\n"]
for store in ("bank1", "cf5", "cf3a"):
    for scope in ("real runs only", "real + degraded copies", "stage-5 subset (real + degraded, minus stray-edit copies of explore tasks)"):
        if scope.startswith("stage-5") and store != "cf5": continue
        rs = [r for r in rows if r["store"] == store and not r["infra"] and (scope != "real runs only" or not r["degradation"])]
        if scope.startswith("stage-5"): rs = [r for r in rs if not (r["degradation"] == "stray-edit" and r["agent"] == "explore")]
        if store == "cf3a": rs = [r for r in rs if "mercury-2.5" in r["model"]]
        if not any(r["judgments"] for r in rs): continue
        if store == "cf3a" and scope != "real runs only": continue
        out.append(f"## {store}{' (mercury-2.5 runs)' if store=='cf3a' else ''}, {scope}: {len(rs)} runs, {sum(1 for r in rs if not r['passed'])} gold failures\n")
        out.append("| path | judge | runs with a verdict | no verdict (runs judged w/o one) | recall | precision | false alarms on good runs | kappa | mean $/judgment | entries |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        keys = sorted({(j["outcome"]["path"], j["outcome"]["judge"]) for r in rs for j in r["judgments"]})
        for path, judge in keys:
            tp = fp = fn = tn = 0; noverd = 0; prices = []; entries = 0
            for r in rs:
                js = [j for j in r["judgments"] if j["outcome"]["path"] == path and j["outcome"]["judge"] == judge]
                if not js: continue
                entries += len(js)
                prices += [j["outcome"]["listPrice"] for j in js if j["outcome"].get("listPrice") is not None]
                vs = [j["outcome"]["verdict"] for j in js if j["outcome"].get("verdict") is not None]
                if not vs: noverd += 1; continue
                flag = vs[-1] <= 1; fail = not r["passed"]
                if flag and fail: tp += 1
                elif flag: fp += 1
                elif fail: fn += 1
                else: tn += 1
            k = kappa(tp, fp, fn, tn)
            out.append(f"| {path} | {short(judge)} | {tp+fp+fn+tn} | {noverd} | {pct(tp, tp+fn)} | {pct(tp, tp+fp)} | {pct(fp, fp+tn)} | {'–' if k is None else f'{k:.2f}'} | {('$%.5f' % st.mean(prices)) if prices else '–'} | {entries} |")
        out.append("")
open(sys.argv[2], "w").write("\n".join(out))
print("\n".join(out))
