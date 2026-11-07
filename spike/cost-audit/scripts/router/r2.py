import sys, collections, statistics as st, math, re, random
sys.path.insert(0, sys.argv[2])
from common import *
D=sys.argv[1]; out=[]; P=prompts(D)
EPS=0.01
def clip(p): return min(1-EPS, max(EPS, p))
def brier(p,y): return (p-y)**2
def ll(p,y): p=clip(p); return -(y*math.log(p)+(1-y)*math.log(1-p))
def toks(s):
    s=s.lower(); a=re.findall(r"[a-z0-9_]+", s); b=[x for w in a for x in w.split("_") if x and "_" in w]
    return a+b
def tfidf(texts):
    docs={t:collections.Counter(toks(x)) for t,x in texts.items()}
    df=collections.Counter(w for c in docs.values() for w in c); N=len(docs)
    V={}
    for t,c in docs.items():
        v={w:(1+math.log(n))*(math.log(N/df[w])+1) for w,n in c.items()}
        z=math.sqrt(sum(x*x for x in v.values())); V[t]={w:x/z for w,x in v.items()}
    def sim(a,b):
        va,vb=V[a],V[b]
        if len(va)>len(vb): va,vb=vb,va
        return sum(x*vb.get(w,0) for w,x in va.items())
    return sim
def run(store, rows, title, configs=None):
    C=cells(rows)
    tasks=sorted({t for t,_ in C})
    cfg=collections.Counter(m for _,m in C)
    models=sorted(m for m,n in cfg.items() if n==len(tasks)) if configs is None else configs
    kind={t:collections.Counter(r["kind"] for r in rows if r["task"]==t).most_common(1)[0][0] for t in tasks}
    text={t:P[store+"|"+t] for t in tasks}
    loglen={t:math.log(len(text[t])) for t in tasks}
    sdl=st.pstdev(loglen.values()) or 1
    sim=tfidf(text)
    def fsim(a,b): return -((kind[a]!=kind[b]) + abs(loglen[a]-loglen[b])/sdl)
    y={(t,m):C[(t,m)]["rate"] for t in tasks for m in models}
    cost={(t,m):C[(t,m)]["cost"] for t in tasks for m in models}
    out.append(f"\n## {title}: {len(tasks)} tasks × {len(models)} configurations ({sum(C[(t,m)]['n'] for t in tasks for m in models)} runs; overall pass {100*st.mean(y.values()):.1f}%; cells with 0<rate<1 or fail: {sum(1 for v in y.values() if v<1)})\n")
    # nearest-neighbour sanity
    ex=[]
    for t in tasks[:6]:
        nb=sorted((x for x in tasks if x!=t), key=lambda x:-sim(t,x))[:3]
        ex.append((t,kind[t],", ".join(f"{x} ({sim(t,x):.2f})" for x in nb)))
    methods=["constant","prior (config mean, raw)","prior (smoothed, a=2)","kNN text k=3","kNN text k=5","kNN text k=5 + prior (m=5)","kNN card k=3","kNN card k=5","kNN card k=5 + prior (m=5)","random k=5 (null, 50 draws)","prior + kNN-text task-effect k=5","prior + kNN-card task-effect k=5","oracle task-effect (cheat)"]
    scores={mm:[0,0] for mm in methods}; per_task={mm:collections.defaultdict(float) for mm in methods}
    preds={mm:{} for mm in methods}
    rng=random.Random(7)
    estcost={}
    for t in tasks:
        tr=[x for x in tasks if x!=t]
        g=st.mean(y[(x,m)] for x in tr for m in models)
        nt=sorted(tr,key=lambda x:-sim(t,x)); nf=sorted(tr,key=lambda x:-fsim(t,x))
        draws=[rng.sample(tr,5) for _ in range(50)]
        for m in models:
            raw=st.mean(y[(x,m)] for x in tr); sm=(raw*len(tr)+2*g)/(len(tr)+2)
            estcost[(t,m)]=st.mean(cost[(x,m)] for x in tr)
            k3=st.mean(y[(x,m)] for x in nt[:3]); k5=st.mean(y[(x,m)] for x in nt[:5])
            f3=st.mean(y[(x,m)] for x in nf[:3]); f5=st.mean(y[(x,m)] for x in nf[:5])
            # cheat: true task effect added to prior (upper bound for any task-level predictor sharing a difficulty shift)
            teff=st.mean(y[(t,mm)] for mm in models)-g
            kte=st.mean(y[(x,mm)] for x in nt[:5] for mm in models)-g
            kfe=st.mean(y[(x,mm)] for x in nf[:5] for mm in models)-g
            P_={"constant":g,"prior (config mean, raw)":raw,"prior (smoothed, a=2)":sm,"kNN text k=3":k3,"kNN text k=5":k5,
                "kNN text k=5 + prior (m=5)":(5*k5+5*sm)/10,"kNN card k=3":f3,"kNN card k=5":f5,"kNN card k=5 + prior (m=5)":(5*f5+5*sm)/10,
                "oracle task-effect (cheat)":min(1,max(0,sm+teff)),
                "prior + kNN-text task-effect k=5":min(1,max(0,sm+kte)),"prior + kNN-card task-effect k=5":min(1,max(0,sm+kfe))}
            for mm,p in P_.items():
                b=brier(clip(p),y[(t,m)]); scores[mm][0]+=b; scores[mm][1]+=ll(p,y[(t,m)]); per_task[mm][t]+=b; preds[mm][(t,m)]=p
            rb=rl=0
            for d in draws:
                p=st.mean(y[(x,m)] for x in d); rb+=brier(clip(p),y[(t,m)]); rl+=ll(p,y[(t,m)])
            scores[methods[9]][0]+=rb/50; scores[methods[9]][1]+=rl/50; per_task[methods[9]][t]+=rb/50
    n=len(tasks)*len(models)
    base="prior (smoothed, a=2)"
    def boot(a,b):
        d=[per_task[a][t]-per_task[b][t] for t in tasks]; r=random.Random(1); bs=[]
        for _ in range(2000):
            s=[d[r.randrange(len(d))] for _ in d]; bs.append(sum(s)/n)
        bs.sort(); return bs[50],bs[1949]
    R=[]
    for mm in methods:
        lo,hi=boot(mm,base) if mm!=base else (0,0)
        R.append((mm,f"{scores[mm][0]/n:.5f}",f"{scores[mm][1]/n:.4f}",f"{100*(1-scores[mm][0]/scores[base][0]):+.1f}%", f"[{lo:+.5f}, {hi:+.5f}]" if mm!=base else "–"))
    out.append("Leave-one-task-out prediction of each configuration's pass rate on the held-out task (cells weighted equally; probabilities clipped to [0.01, 0.99]; Brier/log loss against the cell's observed pass rate).\n")
    out.append(md(["predictor","Brier","log loss","Brier skill vs smoothed prior","Δ Brier vs prior, 95% task-bootstrap CI"],R))
    lo,hi=boot("kNN text k=5","random k=5 (null, 50 draws)")
    out.append(f"\nkNN text k=5 minus random k=5 Brier, 95% task-bootstrap CI: [{lo:+.5f}, {hi:+.5f}] (negative = text neighbours beat random neighbours).")
    pr=sorted(st.mean(y[(t,m)] for t in tasks) for m in models)
    out.append(f"Spread of configuration pass rates (all tasks): min {pr[0]:.2f}, P10 {pr[len(pr)//10]:.2f}, median {st.median(pr):.2f}, P90 {pr[9*len(pr)//10]:.2f}; configurations at 100%: {sum(1 for p in pr if p==1)}/{len(pr)}. Spread of task pass rates (all configs): " + ", ".join(f"{t} {st.mean(y[(t,m)] for m in models):.2f}" for t in sorted(tasks,key=lambda t: st.mean(y[(t,m)] for m in models))[:5]) + " (five hardest).")
    out.append("\nNearest neighbours by TF-IDF cosine (first six tasks, sanity check):\n")
    out.append(md(["task","kind","3 nearest (cosine)"],ex))
    # router simulation
    def route(pred, thr):
        pc=[];cc=[];ch=collections.Counter()
        for t in tasks:
            ok=[m for m in models if pred[(t,m)]>=thr]
            m=min(ok,key=lambda m:estcost[(t,m)]) if ok else max(models,key=lambda m:(pred[(t,m)],-estcost[(t,m)]))
            pc.append(y[(t,m)]); cc.append(cost[(t,m)]); ch[short(m)]+=1
        return st.mean(pc),st.mean(cc),ch
    R=[]
    for nm,m in (("always ling-3.0-flash",LING),("always Haiku 5.5",HAIKU)):
        if m in models: R.append((nm,"–",f"{100*st.mean(y[(t,m)] for t in tasks):.2f}%",f"{st.mean(cost[(t,m)] for t in tasks):.5f}","–"))
    # cheapest config perfect on the training tasks (per fold)
    pc=[];cc=[];ch=collections.Counter()
    for t in tasks:
        tr=[x for x in tasks if x!=t]; ok=[m for m in models if all(y[(x,m)]==1 for x in tr)]
        m=min(ok,key=lambda m:estcost[(t,m)]) if ok else max(models,key=lambda m:st.mean(y[(x,m)] for x in tr))
        pc.append(y[(t,m)]); cc.append(cost[(t,m)]); ch[short(m)]+=1
    R.append(("always cheapest config perfect on the other tasks","–",f"{100*st.mean(pc):.2f}%",f"{st.mean(cc):.5f}",", ".join(f"{k}×{v}" for k,v in ch.most_common(3))))
    for mm in (base,"kNN text k=5","kNN text k=5 + prior (m=5)","kNN card k=5 + prior (m=5)","prior + kNN-text task-effect k=5","oracle task-effect (cheat)"):
        for thr in (0.9,0.95,0.98):
            p,c,ch=route(preds[mm],thr)
            R.append((f"router: {mm}",thr,f"{100*p:.2f}%",f"{c:.5f}",", ".join(f"{k}×{v}" for k,v in ch.most_common(3))))
    out.append("\nRouter simulation: for each held-out task, the cheapest configuration (by its mean cost on the training tasks) whose predicted pass probability ≥ threshold; if none, the highest predicted. Realized pass = that configuration's observed rate on the held-out task; realized cost = its observed mean $/run there.\n")
    out.append(md(["policy","threshold","realized pass","mean $/run","configs chosen (top 3)"],R))
    return scores
out.append("# R2. Is failure predictable from the task text?\n")
out.append("Hypothesis: if a task's text predicts which configurations fail it, a kNN over task embeddings should beat each configuration's own mean (the prior) in Brier score, and a router built on it should beat always-one-model on cost at equal pass rate.\n")
out.append("Method: leave-one-task-out. TF-IDF (sublinear tf, idf over the store's task prompts, word + underscore-split identifier tokens) cosine kNN; card kNN uses distance = [kind differs] + |Δ log prompt chars| / sd. 'kNN + prior' = (k·kNN mean + m·prior)/(k+m), a Bayesian shrink. 'random k=5' averages 50 random draws of 5 training tasks: the null for 'similarity carries information'. 'oracle task-effect (cheat)' adds the held-out task's true mean difficulty shift to the prior: the ceiling for any predictor that only learns a per-task difficulty.\n")
rows=load(D,{"cf2"}); run("cf2",rows,"cf2 (configurations with all 28 tasks)"); del rows
rows=load(D,{"cf3a"}); run("cf3a",rows,"cf3a (all 25 models)"); del rows
rows=load(D,{"cf6"}); run("cf6",rows,"cf6 (3 models, 10-trial rates; deepseek at charged cost)"); del rows
open(sys.argv[3],"w").write("\n".join(out)+"\n"); print("\n".join(out))
