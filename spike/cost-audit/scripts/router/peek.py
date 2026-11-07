import json, collections, statistics as st, sys
rows=[json.loads(l) for l in open(sys.argv[1]+"/rows.jsonl")]
P=json.load(open(sys.argv[1]+"/prompts.json"))
for s in ["cf2","cf3a","cf3b","cf6"]:
    R=[r for r in rows if r["store"]==s]
    cfg=collections.Counter(r["model"] for r in R); tasks=collections.Counter(r["task"] for r in R)
    cov=collections.Counter(len({r["task"] for r in R if r["model"]==m}) for m in cfg)
    print(s, "configs",len(cfg),"tasks",len(tasks),"task coverage hist",dict(cov))
    print("  unpriced runs",sum(1 for r in R if r["listPrice"] is None),"charged present",sum(1 for r in R if r["charged"] is not None),"seconds none",sum(1 for r in R if r["seconds"] is None))
    print("  kinds",dict(collections.Counter(r["kind"] for r in R)), "agents",dict(collections.Counter(r["agent"] for r in R)))
    print("  pass",sum(r["passed"] for r in R)/len(R))
    print("  runs/cell hist", dict(collections.Counter(collections.Counter((r["task"],r["model"]) for r in R).values())))
d=[r for r in rows if r["store"]=="cf6" and "deepseek" in r["model"]]
print("cf6 deepseek list mean",st.mean(r["listPrice"] for r in d),"charged mean",st.mean(r["charged"] for r in d if r["charged"] is not None), sum(r["charged"] is not None for r in d))
for s in ["cf6","cf3a"]:
  for m in ["openrouter:inclusionai/ling-3.0-flash","openrouter:anthropic/claude-haiku-5.5"]:
    d=[r for r in rows if r["store"]==s and r["model"]==m]
    print(s,m,"list",st.mean(r["listPrice"] for r in d),"charged",st.mean(r["charged"] for r in d if r["charged"] is not None))
# endpoints in cf2
print(collections.Counter(r["model"].split(":")[0] for r in rows if r["store"]=="cf2"))
k=list(P)[0]; print(k, list(P[k].values())[0][:600])
print(sorted(set(k.split("|")[1] for k in P if k.startswith("cf3a"))))
print(sorted(set(k.split("|")[1] for k in P if k.startswith("cf2"))))
print(sorted(set(k.split("|")[1] for k in P if k.startswith("cf6"))))
