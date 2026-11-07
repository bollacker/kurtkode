#!/usr/bin/env python3
"""One row per skill from all result files: the final numbers for TAXONOMY_FINAL.md and RESULTS.md.

Task arms on Gemini 3.6 Flash take the latest round for a case's skills/forced arms (r3 > r2 > r1: the skill text
changed between rounds); baseline and control come from r1 (they don't depend on the skill). Argon and Qwen from
their own files. Trigger recall from the Flash run with the AGENTS.md snippet (and without, for comparison).
Usage: summarize.py [--markdown]"""
import json, sys, collections
from pathlib import Path

R = Path(__file__).parent / "results"


def load(name):
    p = R / name
    return [json.loads(l) for l in open(p)] if p.exists() else []


def rate(rs):
    return (sum(r["pass"] for r in rs), len(rs))


def fmt(kn):
    k, n = kn
    return f"{k}/{n}" if n else "–"


def main():
    md = "--markdown" in sys.argv
    flash = {"r1": load("task-gemini36-r1.jsonl") + load("task-gemini36-r1-skills.jsonl"),
             "r2": load("task-gemini36-r2.jsonl"), "r3": load("task-gemini36-r3.jsonl")}
    argon = load("task-argon-r1.jsonl")
    qwen = load("task-qwen35-r1.jsonl")
    trig = load("trigger-gemini36-steps8-agentsmd.jsonl")
    trig0 = load("trigger-gemini36-steps8.jsonl")
    trigq = load("trigger-qwen35-steps8-agentsmd.jsonl")
    cases = sorted({(r["skill"], r["case"]) for r in flash["r1"]})
    rows = []
    for skill, case in cases:
        def arm(src, a):
            return [r for r in src if r["case"] == case and r["arm"] == a]
        latest = {}
        for a in ("skills", "forced"):
            for rnd in ("r3", "r2", "r1"):
                rs = arm(flash[rnd], a)
                if rs:
                    latest[a] = (rnd, rs)
                    break
        def recall(src):
            rs = [r for r in src if r["skill"] == skill and r["expect"]]
            return (sum(r["hit"] for r in rs), len(rs))
        rows.append({
            "skill": skill, "case": case,
            "f_base": rate(arm(flash["r1"], "baseline")), "f_ctrl": rate(arm(flash["r1"], "control")),
            "f_lib": rate(latest.get("skills", ("", []))[1]), "f_forced": rate(latest.get("forced", ("", []))[1]),
            "round": max(latest.get("skills", ("r1",))[0], latest.get("forced", ("r1",))[0]),
            "a_base": rate(arm(argon, "baseline")), "a_lib": rate(arm(argon, "skills")),
            "q_base": rate(arm(qwen, "baseline")), "q_forced": rate(arm(qwen, "forced")),
            "trig": recall(trig), "trig0": recall(trig0), "trigq": recall(trigq),
        })
    for r in rows:
        b = r["f_base"][0] / max(1, r["f_base"][1])
        c = r["f_ctrl"][0] / max(1, r["f_ctrl"][1]) if r["f_ctrl"][1] else b
        f = r["f_forced"][0] / max(1, r["f_forced"][1])
        l = r["f_lib"][0] / max(1, r["f_lib"][1])
        best = max(f, l)
        if best - max(b, c) >= 0.6:
            v = "helps"
        elif best - max(b, c) >= 0.3:
            v = "helps a little"
        elif b >= 0.99 and best >= 0.99:
            v = "ceiling"
        elif max(b, c) - best >= 0.3:
            v = "hurts"
        else:
            v = "no clear effect"
        r["verdict"] = v
    head = ["skill", "case", "Flash none", "Flash control", "Flash library", "Flash forced", "Argon none",
            "Argon library", "Qwen none", "Qwen forced", "recall (snippet)", "recall (none)", "Qwen recall", "verdict"]
    out = [[r["skill"], r["case"], fmt(r["f_base"]), fmt(r["f_ctrl"]), fmt(r["f_lib"]), fmt(r["f_forced"]),
            fmt(r["a_base"]), fmt(r["a_lib"]), fmt(r["q_base"]), fmt(r["q_forced"]), fmt(r["trig"]),
            fmt(r["trig0"]), fmt(r["trigq"]), r["verdict"] + (f" ({r['round']})" if r["round"] != "r1" else "")]
           for r in rows]
    def tot(key):   # trigger recall belongs to the skill, not the case: count each skill once
        rs = list({r["skill"]: r for r in rows}.values()) if key.startswith("trig") else rows
        return (sum(r[key][0] for r in rs), sum(r[key][1] for r in rs))
    out.append(["ALL", "", *(fmt(tot(k)) for k in ("f_base", "f_ctrl", "f_lib", "f_forced", "a_base", "a_lib",
                                                  "q_base", "q_forced", "trig", "trig0", "trigq")),
                " ".join(f"{k}={v}" for k, v in collections.Counter(r["verdict"] for r in rows).most_common())])
    if md:
        print("| " + " | ".join(head) + " |\n|" + "---|" * len(head))
        for o in out:
            print("| " + " | ".join(o) + " |")
    else:
        w = [max(len(x[i]) for x in out + [head]) for i in range(len(head))]
        for o in [head] + out:
            print("  ".join(x.ljust(w[i]) for i, x in enumerate(o)))


if __name__ == "__main__":
    main()
