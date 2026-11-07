#!/usr/bin/env python3
"""Does the skill router's side question cost a local server its prompt cache?

Two-turn sessions in a copy of the neutral fixture: turn 1 builds up history, turn 2 is a request the router sends to
a skill. With the router on, its question runs just before turn 2's first agent request; if that question pushed the
session's prompt out of the server's cache, the agent request reprocesses everything and its time to first token jumps.
Compares that request's time to first token, router on vs off, alternating, N trials each.

Usage: cache_check.py --model bang:qwen/qwen3.5-9b --kk PATH [--trials 3]
"""
import argparse, glob, json, os, shutil, subprocess, time, uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
SESSIONS = Path.home() / "Library/Application Support/kurtkode/sessions"
TURN1 = "Explain what this project does: read the main modules and the tests, then summarize them."
TURN2 = "tests/test_models.py::test_value fails maybe one CI run in five but always passes alone. What would you check first?"


def run(kk, project, prompt, model, router, cont):
    cmd = [kk, "-p", prompt, "-m", model, "--mode", "plan", "--no-mcp", "--no-subagents", "--max-steps", "6" if not cont else "2",
           "--output", "json", "-C", str(project), "--skill-router", router] + (["-c"] if cont else [])
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    return json.loads(p.stdout.strip().splitlines()[-1])


def turn2_first_reply(sid):
    f = glob.glob(str(SESSIONS / "*" / f"{sid}.jsonl"))[0]
    users, routed, out = 0, False, None
    for line in open(f):
        r = json.loads(line)
        if r["type"] == "message" and r["message"]["role"] == "user" and not r["message"].get("contextNote"):
            users += 1
        if users == 2 and r["type"] == "cost":
            c = r["cost"]
            if c.get("purpose") == "routing":
                routed = True
                continue
            if c.get("purpose") == "reply" and out is None:
                out = {"ttft": c.get("timeToFirstToken"), "prompt_tokens": (c.get("tokens") or {}).get("input"),
                       "routing_before": routed}
    return out, Path(f).parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="bang:qwen/qwen3.5-9b")
    ap.add_argument("--kk", required=True)
    ap.add_argument("--trials", type=int, default=3)
    a = ap.parse_args()
    work = HERE / "runs"
    results = []
    for t in range(a.trials):
        for router in ("off", "on"):
            proj = work / f"kkskill-cache-{router}-{uuid.uuid4().hex[:6]}"
            shutil.copytree(HERE / "fixtures" / "_neutral", proj)
            subprocess.run("git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init", shell=True, cwd=proj)
            j1 = run(a.kk, proj, TURN1, a.model, router, False)
            j2 = run(a.kk, proj, TURN2, a.model, router, True)
            info, folder = turn2_first_reply(j2["session"])
            results.append({"trial": t, "router": router, **(info or {})})
            print(results[-1], flush=True)
            shutil.move(str(folder), Path.home() / ".Trash" / f"{folder.name}-{uuid.uuid4().hex[:4]}")
    for router in ("off", "on"):
        rs = [r["ttft"] for r in results if r["router"] == router and r.get("ttft") is not None]
        print(f"router {router}: turn-2 first request time to first token {', '.join(f'{x:.1f}s' for x in rs)}")


if __name__ == "__main__":
    main()
