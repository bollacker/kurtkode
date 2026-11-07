# Extract compact per-run records (no transcript text) from selected stores -> data2/<store>.jsonl
import json, os, sys
root = "/Users/me/git/kurtkode/eval-results/runs"
outdir = sys.argv[1]
for store in sys.argv[2:]:
    sd = os.path.join(root, store)
    n = 0
    with open(os.path.join(outdir, store + ".jsonl"), "w") as out:
        for rid in sorted(os.listdir(sd)):
            p = os.path.join(sd, rid, "run.json")
            if not os.path.exists(p): continue
            d = json.load(open(p))
            if d.get("degradation") or d.get("infra"): continue
            rr = d.get("runRecord") or {}
            tot = rr.get("totals") or {}
            reqs = []
            for m in d.get("transcript") or []:
                mt = m.get("meta") or {}
                u = mt.get("usage")
                if m.get("role") == "assistant" and u:
                    reqs.append([u.get("promptTokens") or 0, u.get("cacheReadTokens") or 0, u.get("cacheWriteTokens") or 0,
                                 u.get("completionTokens") or 0, u.get("reasoningTokens") or 0, u.get("cost"), mt.get("duration")])
            gold = d.get("gold") or {}
            out.write(json.dumps(dict(store=store, id=d.get("id"), model=d.get("model"), task=d.get("task"), kind=d.get("kind"), agent=d.get("agent"),
                trial=d.get("trial"), passed=gold.get("passed"), notes=gold.get("notes"), report=d.get("report") or "",
                listPrice=d.get("listPrice"), charged=tot.get("charged"), lp=tot.get("listPrice"), seconds=d.get("seconds"),
                modelSeconds=tot.get("modelSeconds"), steps=d.get("steps"), stop=d.get("stop"),
                promptTokens=tot.get("promptTokens"), cacheRead=tot.get("cacheReadTokens"), cacheWrite=tot.get("cacheWriteTokens"),
                completion=tot.get("completionTokens"), reqs=reqs)) + "\n")
            n += 1
    print(store, n, flush=True)
