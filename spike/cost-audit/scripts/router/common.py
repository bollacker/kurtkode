import json, collections, statistics as st, math
LING="openrouter:inclusionai/ling-3.0-flash"; HAIKU="openrouter:anthropic/claude-haiku-5.5"
DS="openrouter:deepseek/deepseek-v4-flash-0731#off"
OPUS="openrouter:anthropic/claude-opus-5.5"; SONNET="openrouter:anthropic/claude-sonnet-5.5"
def load(d, stores):
    out=[]
    with open(d+"/rows.jsonl") as f:
        for l in f:
            r=json.loads(l)
            if r["store"] in stores: out.append(r)
    return out
def prompts(d):
    P=json.load(open(d+"/prompts.json"))
    return {k: list(v.values())[0] for k,v in P.items()}
def short(m):
    m=m.split(":",1)[1]; return m.split("/",1)[1] if "/" in m else m
def cost(r, ds_mode="charged"):
    # cf6 deepseek: listPrice inflated ~6x. 'charged' = runRecord.totals.charged; 'typical' = scaled to $0.00045 mean
    if r["store"]=="cf6" and r["model"]==DS:
        if ds_mode=="typical": return r["charged"]*0.00045/0.0018266
        return r["charged"]
    return r["listPrice"] if r["listPrice"] is not None else r["charged"]
def cells(rows, ds_mode="charged"):
    """(task, model) -> dict(n, k, rate, cost, trials{trial:passed})"""
    g=collections.defaultdict(list)
    for r in rows: g[(r["task"], r["model"])].append(r)
    C={}
    for key,v in g.items():
        k=sum(r["passed"] for r in v)
        C[key]=dict(n=len(v), k=k, rate=k/len(v), cost=st.mean(cost(r,ds_mode) for r in v), trials={r["trial"]:r["passed"] for r in v})
    return C
def spearman(x, y):
    def rank(a):
        idx=sorted(range(len(a)), key=lambda i:a[i]); r=[0.0]*len(a); i=0
        while i<len(a):
            j=i
            while j+1<len(a) and a[idx[j+1]]==a[idx[i]]: j+=1
            for t in range(i,j+1): r[idx[t]]=(i+j)/2+1
            i=j+1
        return r
    rx,ry=rank(x),rank(y); mx,my=st.mean(rx),st.mean(ry)
    num=sum((a-mx)*(b-my) for a,b in zip(rx,ry)); den=math.sqrt(sum((a-mx)**2 for a in rx)*sum((b-my)**2 for b in ry))
    return num/den if den else float("nan")
def md(headers, rows):
    o=["| "+" | ".join(headers)+" |", "|"+"---|"*len(headers)]
    for r in rows: o.append("| "+" | ".join(str(c) for c in r)+" |")
    return "\n".join(o)
