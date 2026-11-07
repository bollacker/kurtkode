import sys, collections, statistics as st
sys.path.insert(0, sys.argv[2])
from common import *
D=sys.argv[1]; out=[]
rows=load(D,{"cf2","cf3a","cf6"})
C={s:cells([r for r in rows if r["store"]==s]) for s in ("cf2","cf3a","cf6")}
del rows
out.append("# R2 addendum. Test-retest: is a (task, model) failure persistent across independent stores?\n")
out.append("Any router (kNN or otherwise) can only work if a model's failure on a task recurs. cf6 re-ran the cf2 bank tasks and the cf3a hard tasks with the same three models (10 trials per cell in each store). Below: tasks with ≥1 failure in either store, failed/trials.\n")
R=[]; agree=collections.Counter()
for a,b in (("cf2","cf6"),("cf3a","cf6")):
    for m in (LING,DS,HAIKU):
        ts=sorted({t for (t,mm) in C[a] if mm==m} & {t for (t,mm) in C[b] if mm==m})
        if not ts: continue
        fa=[t for t in ts if C[a][(t,m)]["rate"]<1]; fb=[t for t in ts if C[b][(t,m)]["rate"]<1]
        both=set(fa)&set(fb)
        x=[C[a][(t,m)]["rate"] for t in ts]; y=[C[b][(t,m)]["rate"] for t in ts]
        rho=spearman(x,y) if len(set(x))>1 and len(set(y))>1 else float("nan")
        detail="; ".join(f"{t} {C[a][(t,m)]['n']-C[a][(t,m)]['k']}/{C[a][(t,m)]['n']}→{C[b][(t,m)]['n']-C[b][(t,m)]['k']}/{C[b][(t,m)]['n']}" for t in sorted(set(fa)|set(fb)))
        R.append((f"{a}→{b}",short(m),len(ts),len(fa),len(fb),len(both),f"{rho:+.2f}",detail))
out.append(md(["stores","model","shared tasks","tasks failing in first","in second","in both","Spearman of per-task rates","failures first→second"],R))
open(sys.argv[3],"w").write("\n".join(out)+"\n"); print("\n".join(out))
