#!/usr/bin/env python3
"""Cost-floor stage 0 (COST_FLOOR_PLAN.md): OpenRouter's public model list -> the candidate configurations, cheapest
first, one `openrouter:<id>` per line, with a `#off` twin for models that can reason. Also writes the catalog
with prices as JSON. Usage: costfloor_catalog.py models.json out-dir"""
import json, sys, os

src, out = sys.argv[1], sys.argv[2]
data = json.load(open(src))["data"]

def price(m, k):
    try: return float(m["pricing"][k]) * 1e6
    except (KeyError, TypeError, ValueError): return None

def eligible(m):
    i = m["id"]
    return ("tools" in (m.get("supported_parameters") or []) and (m.get("context_length") or 0) >= 32000
            and not i.startswith("~") and not i.startswith("openrouter/") and not i.endswith(":free")
            and (price(m, "prompt") or -1) >= 0 and (price(m, "completion") or -1) >= 0
            and not (price(m, "prompt") == 0 and price(m, "completion") == 0))

cands = [m for m in data if eligible(m)]
# Variants (`:batch`, `:nitro`, `:thinking`, ...) are dropped when their base model is listed; dated snapshots are
# kept only when no undated id shares their canonical slug.
ids = {m["id"] for m in cands}
kept, seen_slugs = [], set()
for m in sorted(cands, key=lambda m: (":" in m["id"], len(m["id"]))):
    base = m["id"].split(":")[0]
    if ":" in m["id"] and base in ids: continue
    slug = m.get("canonical_slug") or m["id"]
    if slug in seen_slugs: continue
    seen_slugs.add(slug); kept.append(m)

TYPICAL_IN, TYPICAL_OUT = 16_000, 1_200
rows = []
for m in kept:
    cost = TYPICAL_IN * price(m, "prompt") / 1e6 + TYPICAL_OUT * price(m, "completion") / 1e6
    reasons = "reasoning" in (m.get("supported_parameters") or [])
    rows.append({"id": m["id"], "name": m.get("name"), "context": m.get("context_length"), "in_per_m": price(m, "prompt"),
                 "out_per_m": price(m, "completion"), "typical_run": round(cost, 6), "reasons": reasons})
rows.sort(key=lambda r: r["typical_run"])
os.makedirs(out, exist_ok=True)
json.dump(rows, open(os.path.join(out, "catalog.json"), "w"), indent=1)
with open(os.path.join(out, "models-all.txt"), "w") as f:
    f.write("# cost-floor stage 1: every paid tool-capable model, cheapest first; #off = reasoning turned off\n")
    for r in rows:
        f.write(f"openrouter:{r['id']}\n")
        if r["reasons"]: f.write(f"openrouter:{r['id']}#off\n")
configs = sum(2 if r["reasons"] else 1 for r in rows)
est = sum(r["typical_run"] * (2 if r["reasons"] else 1) for r in rows) * 6
print(f"{len(cands)} eligible ids -> {len(rows)} models, {configs} configurations; 6 runs each at typical cost ~${est:.2f}")
over = [r for r in rows if r["typical_run"] > 0.05]
print(f"{len(over)} models over $0.05 a run (screened last); priciest: {over[-1]['id'] if over else '-'} ${rows[-1]['typical_run']:.3f}")
