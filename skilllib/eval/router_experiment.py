#!/usr/bin/env python3
"""Offline skill-router experiments on the trigger set: given a request and the skill list, pick one skill or none.

Strategies:
  llm      ask a model (OpenAI-compatible endpoint, no key) one short classification question
  lexical  score each skill by words shared with its name and description (BM25-like), no model

Usage: router_experiment.py --strategy llm --base http://192.168.1.20:1234/v1 --model qwen/qwen3.5-9b [--reasoning none]
       router_experiment.py --strategy lexical
Writes results/router-<strategy>-<tag>.jsonl and prints recall (should → own skill), own-skill false loads on near
misses, how often near misses route to some skill, and latency.
"""
import argparse, concurrent.futures as cf, glob, json, math, re, time, urllib.request
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILLS = HERE.parent / "skills"


def skills():
    out = []
    for f in sorted(glob.glob(str(SKILLS / "*" / "SKILL.md"))):
        s = open(f).read()
        out.append((re.search(r"^name:\s*(.*)$", s, re.M).group(1).strip(),
                    re.search(r"^description:\s*(.*)$", s, re.M).group(1).strip()))
    return out


def cases():
    for f in sorted(glob.glob(str(HERE / "cases" / "*" / "cases.json"))):
        skill = Path(f).parent.name
        t = json.load(open(f)).get("triggers", {})
        for p in t.get("should", []):
            yield skill, True, p
        for p in t.get("should_not", []):
            yield skill, False, p


PROMPT = """You route a coding agent's tasks to skills. A skill is a set of instructions for one kind of task.

Skills:
{listing}

Request:
{request}

Which one skill fits this request best? Answer with the skill's name only, exactly as listed, or "none" if no skill \
fits (for example a plain question, or a task none of the skills is for)."""

PROMPT_V2 = PROMPT.replace('fits (for example a plain question, or a task none of the skills is for).',
    'fits. Answer "none" for a question that a short answer settles (what a command, flag, value or function does or '
    'returns, where something is used), for a one-line edit, and for a task none of the skills is for.')


def llm_route(request, sk, a):
    listing = "\n".join(f"- {n}: {d}" for n, d in sk)
    body = {"model": a.model, "messages": [{"role": "user", "content": (PROMPT_V2 if a.v2 else PROMPT).format(listing=listing, request=request)}],
            "temperature": 0, "max_tokens": a.max_tokens}
    if a.reasoning:
        body["reasoning_effort"] = a.reasoning
    req = urllib.request.Request(a.base.rstrip("/") + "/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=120) as r:
        j = json.load(r)
    text = (j["choices"][0]["message"].get("content") or "").strip()
    names = {n for n, _ in sk}
    pick = None
    low = text.lower()
    # the last listed name mentioned wins (models sometimes reason first); "none" only if no name appears
    hits = [(low.rfind(n), n) for n in names if n in low]
    if hits:
        pick = max(hits)[1]
    return pick, time.time() - t0, text[-120:], j.get("usage", {})


WORD = re.compile(r"[a-z][a-z0-9]+")
STOP = set("a an the and or of to in on for with is are be it this that my our we you your i me can please when use "
           "not from by as at so do does how what why which into out up some any all".split())


def toks(s):
    return [w for w in WORD.findall(s.lower()) if w not in STOP]


def lexical_router(sk, threshold):
    docs = {n: toks(n.replace("-", " ") + " " + d.split("Not for")[0]) for n, d in sk}
    df = Counter(w for d in docs.values() for w in set(d))
    N = len(docs)

    def route(request):
        q = set(toks(request))
        scores = {}
        for n, d in docs.items():
            dl = len(d)
            tf = Counter(d)
            s = sum(math.log(1 + N / df[w]) * tf[w] * 2.2 / (tf[w] + 1.2 * (0.25 + 0.75 * dl / 30)) for w in q if w in tf)
            scores[n] = s
        best = max(scores, key=scores.get)
        return (best if scores[best] >= threshold else None), 0.0, f"{scores[best]:.2f}", {}
    return route


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strategy", choices=["llm", "lexical"], default="llm")
    ap.add_argument("--base", default="http://192.168.1.20:1234/v1")
    ap.add_argument("--model", default="qwen/qwen3.5-9b")
    ap.add_argument("--reasoning", default=None)
    ap.add_argument("--max-tokens", type=int, default=400)
    ap.add_argument("--threshold", type=float, default=2.0)
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--tag", default="")
    ap.add_argument("--v2", action="store_true", help="the prompt that says what counts as none")
    a = ap.parse_args()
    sk = skills()
    cs = list(cases())
    if a.limit:
        cs = cs[:: max(1, len(cs) // a.limit)][: a.limit]
    route = (lambda r: llm_route(r, sk, a)) if a.strategy == "llm" else lexical_router(sk, a.threshold)
    out = HERE / "results" / f"router-{a.strategy}{'-' + a.tag if a.tag else ''}.jsonl"
    rows = []
    with cf.ThreadPoolExecutor(a.parallel if a.strategy == "llm" else 1) as ex:
        futs = {ex.submit(route, p): (s, e, p) for s, e, p in cs}
        for f in cf.as_completed(futs):
            s, e, p = futs[f]
            try:
                pick, secs, raw, usage = f.result()
            except Exception as err:
                pick, secs, raw, usage = None, 0, f"ERR {err}", {}
            rows.append({"skill": s, "expect": e, "prompt": p, "pick": pick, "secs": secs, "raw": raw, "usage": usage})
    with open(out, "w") as fh:
        fh.writelines(json.dumps(r) + "\n" for r in rows)
    sh = [r for r in rows if r["expect"]]
    nm = [r for r in rows if not r["expect"]]
    print(f"{a.strategy} {a.tag}: recall {sum(r['pick'] == r['skill'] for r in sh)}/{len(sh)}  "
          f"wrong skill on should {sum(1 for r in sh if r['pick'] and r['pick'] != r['skill'])}  "
          f"none on should {sum(1 for r in sh if not r['pick'])}  |  near misses: own skill {sum(r['pick'] == r['skill'] for r in nm)}/{len(nm)}, "
          f"some skill {sum(1 for r in nm if r['pick'])}  |  errors {sum(1 for r in rows if str(r['raw']).startswith('ERR'))}  "
          f"mean {sum(r['secs'] for r in rows) / max(1, len(rows)):.1f}s")


if __name__ == "__main__":
    main()
