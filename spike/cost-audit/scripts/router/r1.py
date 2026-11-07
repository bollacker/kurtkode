import sys, collections, statistics as st
sys.path.insert(0, sys.argv[2])
from common import *
D=sys.argv[1]; out=[]
def pool_cf6(ds_mode):
    rows=load(D,{"cf6"}); return rows, cells(rows, ds_mode), [LING, DS, HAIKU]
def pool_cf3a():
    rows=load(D,{"cf3a","cf3b"})
    cnt=collections.Counter(r["model"] for r in rows if r["store"]=="cf3a")
    ms=[m for m,c in cnt.items() if c>=100]
    rows=[r for r in rows if (r["store"]=="cf3a" and r["model"] in ms) or (r["store"]=="cf3b" and r["model"] in (OPUS,SONNET))]
    C=cells(rows)
    # frontier priced at their cf3b store-wide mean
    for m in (OPUS,SONNET):
        mc=st.mean(r["listPrice"] for r in rows if r["model"]==m)
        for (t,mm),c in C.items():
            if mm==m: c["cost"]=mc
    return rows, C, ms+[SONNET,OPUS]
def always(C, tasks, m):
    return st.mean(C[(t,m)]["rate"] for t in tasks), st.mean(C[(t,m)]["cost"] for t in tasks)
def mcost(C,tasks,m): return st.mean(C[(t,m)]["cost"] for t in tasks)
def oracle(C, tasks, models, thr, rateC=None, evalC=None):
    """choose per task with rateC (selection) and score with evalC; thr None = match best"""
    rateC=rateC or C; evalC=evalC or C
    chosen={}
    for t in tasks:
        best=max(rateC[(t,m)]["rate"] for m in models)
        bar=best if thr is None else thr
        ok=[m for m in models if rateC[(t,m)]["rate"]>=bar-1e-12]
        if not ok: ok=[m for m in models if rateC[(t,m)]["rate"]>=best-1e-12]
        chosen[t]=min(ok, key=lambda m: rateC[(t,m)]["cost"])
    p=st.mean(evalC[(t,chosen[t])]["rate"] for t in tasks); c=st.mean(evalC[(t,chosen[t])]["cost"] for t in tasks)
    return p,c,collections.Counter(short(m) for m in chosen.values())
def halfC(rows, C, half):
    g=collections.defaultdict(list)
    for r in rows:
        if r["store"]=="cf3b": g[(r["task"],r["model"])].append(r); continue
        if (r["trial"]<=5)==(half==0): g[(r["task"],r["model"])].append(r)
    H={}
    for k,v in g.items():
        H[k]=dict(rate=sum(x["passed"] for x in v)/len(v), cost=C[k]["cost"])  # cost: full-cell mean (cost is not the target)
    return H
def section(name, rows, C, models):
    tasks=sorted({t for t,_ in C})
    out.append(f"\n### {name}: {len(tasks)} tasks, {len(models)} models\n")
    A=[]
    for m in models:
        p,c=always(C,tasks,m); A.append((c,p,m))
    A.sort()
    out.append("(a) Always-X (equal task weight; cost = mean $/run)\n")
    out.append(md(["model","pass rate","mean $/run","tasks with ≥1 fail"], [(short(m),f"{100*p:.1f}%",f"{c:.5f}",sum(1 for t in tasks if C[(t,m)]['rate']<1)) for c,p,m in A]))
    out.append("\n(b) Per-task oracle (in-sample: chooses and is scored on the same trials) and split-half oracle (choose on trials 1–5, score on 6–10, and the reverse; averaged)\n")
    R=[]
    H0,H1=halfC(rows,C,0),halfC(rows,C,1)
    for thr in (None,1.0,0.95,0.9):
        p,c,ch=oracle(C,tasks,models,thr)
        a=oracle(C,tasks,models,thr,H0,H1); b=oracle(C,tasks,models,thr,H1,H0)
        R.append(("match best" if thr is None else f"≥{thr}", f"{100*p:.2f}%", f"{c:.5f}", f"{100*(a[0]+b[0])/2:.2f}%", f"{(a[1]+b[1])/2:.5f}", ", ".join(f"{k}×{v}" for k,v in ch.most_common())))
    out.append(md(["oracle bar","pass (in-sample)","mean $/run","pass (split-half)","$/run (split-half)","models chosen (in-sample)"],R))
    pl,cl=always(C,tasks,LING); ph,chh=always(C,tasks,HAIKU); po,co,_=oracle(C,tasks,models,None)
    out.append(f"\nHeadline: match-best oracle {100*po:.2f}% at ${co:.5f}/run vs always-ling {100*pl:.2f}% at ${cl:.5f} ({co/cl:.2f}× ling's cost, {100*(po-pl):+.2f} pts) and always-Haiku {100*ph:.2f}% at ${chh:.5f} ({100*(1-co/chh):.0f}% cheaper than Haiku, {100*(po-ph):+.2f} pts).\n")
    return tasks
def contain(C, tasks, a, b):
    fa=[(t,tr) for t in tasks for tr,ok in C[(t,a)]["trials"].items() if not ok]
    both=[x for x in fa if x[1] in C[(x[0],b)]["trials"]]
    bp=sum(1 for t,tr in both if C[(t,b)]["trials"][tr])
    ta=[t for t in tasks if C[(t,a)]["rate"]<1]
    brate=st.mean(C[(t,b)]["rate"] for t in ta) if ta else float("nan")
    better=sum(1 for t in tasks if C[(t,b)]["rate"]>C[(t,a)]["rate"]); worse=sum(1 for t in tasks if C[(t,b)]["rate"]<C[(t,a)]["rate"])
    return (short(a),short(b),len(fa),f"{bp}/{len(both)}" + (f" ({100*bp/len(both):.0f}%)" if both else ""), len(ta), f"{100*brate:.0f}%" if ta else "–", better, worse, len(tasks)-better-worse)
out.append("# R1. Oracle routing headroom\n")
out.append("Hypothesis: if the cheap and dear models fail on different tasks, a per-task router can buy most of the dear model's pass rate at near the cheap model's price; if failures are rare and scattered (noise), the oracle's headroom is tiny and not reproducible on fresh trials.\n")
out.append("Data: cf6 (ling-3.0-flash, deepseek-v4-flash-0731#off, Haiku 5.5; 48 tasks × 10 trials; 1,439 real runs). cf3a (the 12 models with ≥100 runs, i.e. 10 trials on each of the 14 hard tasks) plus Opus 5.5 and Sonnet 5.5 from cf3b (3 trials/task, all pass) priced at their cf3b store means. Cost = run listPrice; cf6 deepseek uses runRecord.totals.charged (mean $0.00183) and, in a second pass, that charge scaled to a $0.00045 mean.\n")
for mode in ("charged","typical"):
    rows,C,ms=pool_cf6(mode)
    tasks=section(f"cf6 (deepseek at {'charged, mean $0.00183' if mode=='charged' else 'typical, mean $0.00045'})", rows, C, ms)
    if mode=="charged":
        cf6C, cf6tasks = C, tasks
rows,C,ms=pool_cf3a(); t3=section("cf3a + frontier", rows, C, ms)
out.append("\n### (c) Solve-set containment\n")
out.append("Cell level pairs the same (task, trial index); trials are independent draws, so this is the chance the other model passes a failed cell, not a matched retry. 'Tasks A fails' = tasks where A's pass rate < 1; 'B's rate there' = B's mean pass rate on those tasks. Last three columns: tasks where B's rate is above / below / equal to A's.\n")
R=[]
for a,b in ((LING,HAIKU),(HAIKU,LING),(LING,DS),(DS,LING),(DS,HAIKU),(HAIKU,DS)): R.append(("cf6",)+contain(cf6C,cf6tasks,a,b))
MERC="openrouter:inception/mercury-2.5"
for a,b in ((LING,HAIKU),(HAIKU,LING),(MERC,LING),(LING,MERC),(LING,OPUS)): R.append(("cf3a",)+contain(C,t3,a,b))
out.append(md(["store","A","B","A's failed cells","B passes same cell","tasks A fails","B's rate there","B>A tasks","B<A tasks","tie"],R))
# per-task failure listing
out.append("\nPer-task failures (failed trials / trials) where any of ling, deepseek#off, Haiku failed, cf6:\n")
R=[]
for t in cf6tasks:
    f=[cf6C[(t,m)]["n"]-cf6C[(t,m)]["k"] for m in (LING,DS,HAIKU)]
    if sum(f): R.append((t,)+tuple(f"{x}/{cf6C[(t,m)]['n']}" for x,m in zip(f,(LING,DS,HAIKU))))
out.append(md(["task","ling","deepseek#off","Haiku"],R))
open(sys.argv[3],"w").write("\n".join(out)+"\n")
print("\n".join(out))
