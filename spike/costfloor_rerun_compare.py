#!/usr/bin/env python3
"""Cost-floor finalists then (cf1+cf2+cf3a: before Phase 1, no skills) and now (cf6: Phase 1 + Round 5, built-in skills)."""
import glob, json, math, os, sys

RUNS = os.path.expanduser("~/git/kurtkode/eval-results/runs")
MODELS = {"inclusionai_ling-3.0-flash": "ling-3.0-flash", "deepseek_deepseek-v4-flash-0731_off": "deepseek-v4-flash-0731#off",
          "anthropic_claude-haiku-5.5": "claude-haiku-5.5"}
# OpenRouter's list prices per token when this is run (input, cache read, output), to reprice old and new runs alike.
import urllib.request
PRICES = {}
for m in json.load(urllib.request.urlopen("https://openrouter.ai/api/v1/models"))["data"]:
    p = m.get("pricing") or {}
    PRICES[m["id"].replace("/", "_")] = (float(p.get("prompt") or 0), float(p.get("input_cache_read") or p.get("prompt") or 0),
                                          float(p.get("completion") or 0))


def wilson(k, n, z=1.96):
    if n == 0: return (0, 0)
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)


def load(stores, key):
    out = []
    for s in stores:
        for d in glob.glob(f"{RUNS}/{s}/*__openrouter_{key}__t*/run.json"):
            r = json.load(open(d))
            t = (r.get("runRecord") or {}).get("totals") or {}
            pi, pc, po = PRICES.get(key.replace("_off", ""), (0, 0, 0))
            cached = t.get("cacheReadTokens") or 0
            today = ((t.get("promptTokens") or 0) - cached) * pi + cached * pc + (t.get("completionTokens") or 0) * po
            out.append({"task": r["task"], "hard": r["task"].startswith("h-"), "pass": bool((r.get("gold") or {}).get("passed")),
                        "today": today,
                        "price": (t.get("listPrice") or {}).get("total") or 0, "charged": t.get("charged") or 0,
                        "prompt": r.get("promptTokens") or 0, "secs": r.get("seconds") or 0, "steps": r.get("steps") or 0,
                        "tools": [c["name"] for m in r.get("transcript", []) for c in (m.get("toolCalls") or [])]})
    return out


def row(name, runs):
    n = len(runs); k = sum(r["pass"] for r in runs)
    if n == 0: return f"| {name} | – |"
    lo, hi = wilson(k, n)
    bank = [r for r in runs if not r["hard"]]; hard = [r for r in runs if r["hard"]]
    price = sum(r["price"] for r in runs) / n
    return (f"| {name} | {sum(r['pass'] for r in bank)}/{len(bank)} | {sum(r['pass'] for r in hard)}/{len(hard)} | "
            f"{100*k/n:.0f}% ({100*lo:.0f}–{100*hi:.0f}%) | ${price:.5f} | ${price*n/max(k,1):.5f} | "
            f"${sum(r['today'] for r in runs)/n:.5f} | "
            f"{sum(r['prompt'] for r in runs)/n:,.0f} | {sum(r['secs'] for r in runs)/n:.0f} | {sum(r['steps'] for r in runs)/n:.1f} |")


print("| model, setup | bank | hard | pass (95% CI) | list $/run (then) | $/success | $/run at today's prices | prompt tok/run | s/run | steps |")
print("|---|---|---|---|---|---|---|---|---|---|")
detail = {}
for key, name in MODELS.items():
    old = load(["cf1", "cf2", "cf3a"], key); new = load(["cf6"], key)
    print(row(f"{name}, then", old)); print(row(f"{name}, now", new))
    detail[name] = (old, new)
print()
for name, (old, new) in detail.items():
    fo = sorted({r["task"] for r in old if not r["pass"]}); fn = {}
    for r in new:
        if not r["pass"]: fn[r["task"]] = fn.get(r["task"], 0) + 1
    skills = sum(t.count("skill") for r in new for t in [r["tools"]])
    print(f"{name}: failed then {sorted(fo)}; now {fn}; skill tool calls now: {skills}")
