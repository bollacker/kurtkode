"""Aggregate prompt-cache usage from Claude Code transcripts (~/.claude/projects/*/*.jsonl, incl. subagents)."""
import json, glob, os, sys, collections, datetime

root = os.path.expanduser("~/.claude/projects")
files = glob.glob(f"{root}/**/*.jsonl", recursive=True)
tot = collections.Counter()
by_model = collections.defaultdict(collections.Counter)
seen = set()
gaps = []          # (gap seconds, cache_read, cache_write, input) for consecutive main-thread requests in a file
first_req = collections.Counter()
for f in files:
    sub = "/subagents/" in f
    last_t = None
    for line in open(f, errors="replace"):
        if '"usage"' not in line: continue
        try: d = json.loads(line)
        except Exception: continue
        m = d.get("message") or {}
        u = m.get("usage")
        if not isinstance(u, dict) or d.get("type") != "assistant": continue
        mid = m.get("id") or d.get("uuid")
        if mid in seen: continue   # streamed messages repeat per content block
        seen.add(mid)
        model = m.get("model", "?")
        if model == "<synthetic>": continue
        cc = u.get("cache_creation") or {}
        row = dict(inp=u.get("input_tokens", 0), read=u.get("cache_read_input_tokens", 0),
                   write=u.get("cache_creation_input_tokens", 0), w1h=cc.get("ephemeral_1h_input_tokens", 0),
                   w5m=cc.get("ephemeral_5m_input_tokens", 0), out=u.get("output_tokens", 0), n=1)
        key = ("sub" if sub else "main")
        for k, v in row.items():
            tot[k] += v or 0; by_model[(model, key)][k] += v or 0
        try: t = datetime.datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
        except Exception: t = None
        if t and last_t and not sub:
            gaps.append(((t - last_t).total_seconds(), row["read"], row["write"], row["inp"]))
        if t: last_t = t

def show(name, c):
    prompt = c["inp"] + c["read"] + c["write"]
    if not prompt: return
    print(f"{name:45s} reqs={c['n']:6d} prompt={prompt/1e6:8.1f}M read={c['read']/prompt:5.1%} "
          f"write={c['write']/prompt:5.1%} (1h {c['w1h']/max(1,c['write']):4.0%}) uncached={c['inp']/prompt:5.2%} out={c['out']/1e6:6.2f}M "
          f"avg_prompt={prompt/c['n']/1000:6.1f}k")

print("files", len(files))
show("TOTAL", tot)
for k, c in sorted(by_model.items(), key=lambda kv: -kv[1]["n"]): show(f"{k[0]} [{k[1]}]", c)

# Equivalent API price of the tokens (Opus 5.5 list: $4 in, $20 out? read from args) — computed as multiples of base input.
prompt = tot["inp"] + tot["read"] + tot["write"]
units_cached = tot["inp"] + 0.1 * tot["read"] + 1.25 * tot["w5m"] + 2 * tot["w1h"]
print(f"\ninput-side cost with caching = {units_cached/prompt:.3f} x of uncached cost  (savings {1-units_cached/prompt:.1%})")
print(f"output tokens / prompt tokens = {tot['out']/prompt:.4f}")

# Idle gaps: how often does the cache go cold, and what happens after long gaps?
buckets = [(0, 60), (60, 300), (300, 3600), (3600, 1e12)]
for lo, hi in buckets:
    sel = [g for g in gaps if lo <= g[0] < hi]
    if not sel: continue
    r = sum(g[1] for g in sel); w = sum(g[2] for g in sel); i = sum(g[3] for g in sel)
    print(f"gap {lo:>5}-{hi if hi < 1e12 else 'inf':>5}s: {len(sel):6d} reqs, read share {r/max(1,r+w+i):5.1%}, write share {w/max(1,r+w+i):5.1%}")

# API-equivalent list prices ($/M): input, output, cache read (kurtkode PriceList, 2026-10-14)
P = {"claude-fable-5-1": (10, 50, 0.25), "claude-fable-5": (10, 50, 1.0), "claude-opus-5-5": (4, 20, 0.20),
     "claude-opus-5": (5, 25, 0.5), "claude-opus-4-8": (5, 25, 0.5), "claude-sonnet-5-5": (2, 10, 0.2),
     "claude-sonnet-5": (2, 10, 0.2), "claude-haiku-5-5": (0.1, 0.5, 0.01), "claude-haiku-4-5-20251001": (1, 5, 0.1)}
parts = collections.Counter()
for (model, _), c in by_model.items():
    p = P.get(model)
    if not p: continue
    i, o, r = p
    parts["uncached"] += c["inp"] * i / 1e6
    parts["read"] += c["read"] * r / 1e6
    parts["write5m"] += c["w5m"] * i * 1.25 / 1e6
    parts["write1h"] += c["w1h"] * i * 2 / 1e6
    parts["output"] += c["out"] * o / 1e6
    parts["nocache_input"] += (c["inp"] + c["read"] + c["write"]) * i / 1e6
total = sum(v for k, v in parts.items() if k != "nocache_input")
print("\nAPI-equivalent $:", {k: round(v) for k, v in parts.items()}, "total", round(total))
print({k: f"{v/total:.0%}" for k, v in parts.items() if k != "nocache_input"})
print(f"same tokens with no caching: ${parts['nocache_input'] + parts['output']:,.0f}")
