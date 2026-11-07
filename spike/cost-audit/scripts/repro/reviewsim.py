import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
def cost(r):
    c = r.get("charged"); return c if c is not None else r.get("listPrice")
groups = ["real-fail", "stray-edit", "undo-all", "undo-half", "vanish", "pass"]
out = ["| reviewer | group | runs | found a problem | of them \"wrong\" | no verdict | a review (mean charged, else list) | summed cost |", "|---|---|---|---|---|---|---|---|"]
for rv in sorted({r["reviewer"] for r in rows}):
    mine = [r for r in rows if r["reviewer"] == rv]
    def line(name, g):
        if not g: return
        j = [r for r in g if r.get("verdict") is not None]; fl = [r for r in j if r["verdict"] != "looks_right"]; w = [r for r in j if r["verdict"] == "wrong"]
        cs = [cost(r) for r in g if cost(r) is not None]
        out.append(f"| {rv} | {name} | {len(g)} | {len(fl)}/{len(j)} ({round(100*len(fl)/len(j)) if j else '–'}%) | {len(w)} | {len(g)-len(j)} | {('$%.5f' % (sum(cs)/len(cs))) if cs else 'free'}, {sum(r['seconds'] for r in g)/len(g):.0f} s | {('$%.4f' % sum(cs)) if cs else '–'} |")
    for g in groups: line(g, [r for r in mine if r["group"] == g])
    line("all failures", [r for r in mine if not r["goldPassed"]])
    line("all 80", mine)
tot = sum(cost(r) or 0 for r in rows)
txt = "Recomputed ReviewSim.report from the stored rows (copy of eval-results/review-sim/bank1-rows.jsonl), python3 -I.\n\n" + "\n".join(out) + f"\n\ntotal cost in rows: ${tot:.4f}\n"
open(sys.argv[2], "w").write(txt); print(txt)
