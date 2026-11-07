import sys, collections, statistics as st, math, random
sys.path.insert(0, sys.argv[2])
from common import *
D=sys.argv[1]; out=[]; P=prompts(D)
EDIT={"edit","fix","refactor","write-tests"}
def perm_p(x,y,rho,n=2000):
    r=random.Random(3); yy=list(y); c=0
    for _ in range(n):
        r.shuffle(yy)
        if abs(spearman(x,yy))>=abs(rho)-1e-12: c+=1
    return (c+1)/(n+1)
def analyse(store, rows, title, models=None):
    if models: rows=[r for r in rows if r["model"] in models]
    tasks=sorted({r["task"] for r in rows})
    g=collections.defaultdict(list)
    for r in rows: g[r["task"]].append(r)
    C=cells(rows)
    F={}
    for t in tasks:
        v=g[t]; txt=P[store+"|"+t]
        cs=[c for (tt,m),c in C.items() if tt==t]
        F[t]=dict(fail=sum(1 for r in v if not r["passed"]), failrate=st.mean(1-c["rate"] for c in cs),
            chars=len(txt), words=len(txt.split()), kind=v[0]["kind"], edit=1 if v[0]["kind"] in EDIT else 0, general=1 if v[0]["agent"]=="general" else 0,
            steps=st.mean(r["steps"] for r in v), pt=st.mean(r["pt"] for r in v), ct=st.mean(r["ct"] for r in v), sec=st.mean(r["seconds"] for r in v),
            files=st.mean(r["nfiles"] for r in v if r["passed"]) if any(r["passed"] for r in v) else 0,
            hard=1 if t.startswith("h-") else 0)
    out.append(f"\n## {title}: {len(tasks)} tasks, {len({r['model'] for r in rows})} models, {len(rows)} runs, {sum(F[t]['fail'] for t in tasks)} failures on {sum(1 for t in tasks if F[t]['fail'])} tasks\n")
    y=[F[t]["failrate"] for t in tasks]
    feats=[("prompt chars","chars"),("prompt words","words"),("edits files (kind ∈ edit/fix/refactor/write-tests)","edit"),("agent = general (vs explore)","general"),("mean files changed (passing runs)","files"),("mean steps","steps"),("mean prompt tokens","pt"),("mean completion tokens","ct"),("mean seconds","sec")]
    if len({F[t]["hard"] for t in tasks})>1: feats.append(("hard-tier task (h- prefix)","hard"))
    R=[]
    for nm,k in feats:
        x=[F[t][k] for t in tasks]; rho=spearman(x,y)
        R.append((nm,"pre-run" if k in ("chars","words","edit","general","hard") else "post-run (outcome-tainted)",f"{rho:+.2f}",f"{perm_p(x,y,rho):.3f}"))
    out.append("Spearman correlation of the task's mean failure rate (over models) with each feature; p = two-sided permutation test (2,000 shuffles).\n")
    out.append(md(["feature","available before routing?","Spearman ρ","perm. p"],R))
    K=collections.defaultdict(list)
    for t in tasks: K[F[t]["kind"]].append(t)
    out.append("\nBy card kind:\n")
    out.append(md(["kind","tasks","tasks with ≥1 failure","failures","mean failure rate"],[(k,len(v),sum(1 for t in v if F[t]["fail"]),sum(F[t]["fail"] for t in v),f"{100*st.mean(F[t]['failrate'] for t in v):.1f}%") for k,v in sorted(K.items(),key=lambda kv:-st.mean(F[t]['failrate'] for t in kv[1]))]))
    hard=sorted(tasks,key=lambda t:-F[t]["failrate"])[:8]
    out.append("\nHardest tasks:\n")
    out.append(md(["task","kind","failures","mean fail rate","prompt chars","mean steps","mean prompt tok","mean seconds"],[(t,F[t]["kind"],F[t]["fail"],f"{100*F[t]['failrate']:.1f}%",F[t]["chars"],f"{F[t]['steps']:.1f}",f"{F[t]['pt']:,.0f}",f"{F[t]['sec']:.0f}") for t in hard]))
    out.append(f"\nAll-task medians for comparison: prompt chars {st.median(F[t]['chars'] for t in tasks):.0f}, steps {st.median(F[t]['steps'] for t in tasks):.1f}, prompt tokens {st.median(F[t]['pt'] for t in tasks):,.0f}, seconds {st.median(F[t]['sec'] for t in tasks):.0f}.")
    return F, C, tasks
def rules(F, C, tasks, up_models, title):
    out.append(f"\n### Static escalation rules, {title}: ling by default, escalate to the named model when the rule fires (in-sample; equal task weight)\n")
    med=st.median(F[t]["chars"] for t in tasks); q75=sorted(F[t]["chars"] for t in tasks)[3*len(tasks)//4]
    R=[]
    def ev(name, fire, up):
        p=st.mean(C[(t,up if fire(t) else LING)]["rate"] for t in tasks); c=st.mean(C[(t,up if fire(t) else LING)]["cost"] for t in tasks)
        R.append((name, short(up), sum(1 for t in tasks if fire(t)), f"{100*p:.2f}%", f"{c:.5f}"))
    for up in up_models:
        ev("never (always ling)", lambda t: False, up)
        ev("always", lambda t: True, up)
        ev("edit-kind tasks", lambda t: F[t]["edit"]==1, up)
        ev("read-only tasks", lambda t: F[t]["edit"]==0, up)
        ev(f"prompt > median ({med:.0f} chars)", lambda t: F[t]["chars"]>med, up)
        ev(f"prompt > P75 ({q75} chars)", lambda t: F[t]["chars"]>q75, up)
        ev("edit-kind and prompt > median", lambda t: F[t]["edit"]==1 and F[t]["chars"]>med, up)
        if any(F[t]["hard"] for t in tasks): ev("hard-tier (h-) tasks", lambda t: F[t]["hard"]==1, up)
    out.append(md(["rule fires on","escalate to","tasks escalated","pass","mean $/run"],R))
out.append("# R3. Difficulty signals cheaper than a router\n")
out.append("Hypothesis: if difficulty tracks something visible before the run (prompt length, kind, editing vs reading), a one-line static rule could capture whatever routing headroom exists without a learned router.\n")
out.append("Data: per-task aggregates. Failure measure = mean over models of the per-model failure rate on that task (equal model weight). 'Post-run' features (steps, tokens, seconds) are means over all models' runs on the task, so they describe how much work the task induced; they are not available to a router before the run but are available to a cascade after a cheap first attempt.\n")
rows=load(D,{"cf6"}); F,C,tasks=analyse("cf6",rows,"cf6"); rules(F,C,tasks,[DS,HAIKU],"cf6 (deepseek#off at charged cost)"); del rows
rows=load(D,{"cf3a"}); F,C,tasks=analyse("cf3a",rows,"cf3a (all 25 models)"); rules(F,C,tasks,[HAIKU,DS],"cf3a"); del rows
rows=load(D,{"cf2"})
cnt=collections.Counter((r["model"]) for r in rows); full={m for m in {r['model'] for r in rows} if len({r['task'] for r in rows if r['model']==m})==28}
analyse("cf2",rows,"cf2 (205 full-coverage configurations)", full); del rows
open(sys.argv[3],"w").write("\n".join(out)+"\n"); print("\n".join(out))
