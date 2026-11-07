#!/usr/bin/env python3
"""Skill tests for the skill library, run through the kurtkode CLI.

Two kinds of test, both read from eval/cases/<skill>/cases.json (kept outside the skills, so a run can't read its
fixtures' answers):

  trigger  Does the model load the right skill for a request, and no skill for a near miss? Each prompt runs in a
           neutral project with the whole library installed, read-only (--mode plan), for a few steps.
  task     Does the skill make the work better? A fixture project and a request, run with the library installed and
           without it (the baseline), each judged by a shell check (exit 0 = pass) and, if the case has a rubric,
           by a judge model reading the transcript.

cases.json:
  {"triggers": {"should": ["..."], "should_not": ["..."]},
   "tasks": [{"id": "...", "fixture": "fixtures/NAME", "prompt": "...", "check": "shell command",
              "rubric": ["criterion", ...], "max_steps": 40}]}

Results are JSON lines (one per run) in --out; `--report` summarizes a results file.
Test projects are made under --work (default: $SKILLEVAL_WORK or ./runs); their kurtkode sessions are moved to the
Trash at the end unless --keep-sessions.
"""
import argparse, concurrent.futures as cf, glob, json, os, re, shutil, subprocess, sys, time, uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE.parent / "skills"
KK = Path(os.environ.get("KK", Path.home() / "git/kurtkode/AgentCore/.build/release/kurtkode"))
BUILTIN = False        # --builtin: rely on kurtkode's built-in skills and prompt line instead of installing the library
NO_BUILTIN_FLAG = []   # ["--no-builtin-skills"] when the binary has built-in skills, for runs that must not see them
ROUTER_FLAG = []       # ["--skill-router", WHEN] from --router
SESSIONS = Path.home() / "Library/Application Support/kurtkode/sessions"
NEUTRAL = HERE / "fixtures" / "_neutral"
CASES = HERE / "cases"
CONTROL = HERE / "fixtures" / "_control_skill"   # a length-matched irrelevant skill, force-loaded in the "control" arm


def sh(cmd, cwd, timeout=120, env=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True, timeout=timeout,
                           env={**os.environ, **(env or {})})
        return p.returncode, (p.stdout + p.stderr)[-4000:]
    except subprocess.TimeoutExpired:
        return 124, "timeout"


AGENTS_MD = None   # set from --agents-md: a file copied into each project as AGENTS.md (git-ignored)


def make_project(fixture, work, tag, library):
    """A copy of the fixture as a git repo with one commit, the library (if any) in .agents/skills, ignored by git.
    A fixture's `_setup.sh`, if any, runs instead of the single commit (to build history, branches, a conflicted
    merge, …) and is removed first; it runs in the project folder with git identity set."""
    d = work / f"kkskill-{tag}-{uuid.uuid4().hex[:6]}"
    shutil.copytree(fixture, d, symlinks=True)
    setup = d / "_setup.sh"
    gitenv = {"GIT_AUTHOR_NAME": "Dana Lee", "GIT_AUTHOR_EMAIL": "dana@example.com",
              "GIT_COMMITTER_NAME": "Dana Lee", "GIT_COMMITTER_EMAIL": "dana@example.com"}
    if setup.exists():
        script = setup.read_text()
        setup.unlink()
        rc, out = sh(script, d, timeout=300, env=gitenv)
        if rc != 0:
            raise RuntimeError(f"fixture setup failed: {out[-500:]}")
    else:
        sh("git init -q -b main && git add -A && git commit -qm 'Initial commit' --allow-empty", d, env=gitenv)
    if library:
        shutil.copytree(library, d / ".agents" / "skills")
        with open(d / ".git" / "info" / "exclude", "a") as f:
            f.write("\n.agents/\n")
        if AGENTS_MD and not (d / "AGENTS.md").exists():
            shutil.copy(AGENTS_MD, d / "AGENTS.md")
            with open(d / ".git" / "info" / "exclude", "a") as f:
                f.write("AGENTS.md\n")
    return d


def session_file(sid):
    hits = glob.glob(str(SESSIONS / "*" / f"{sid}.jsonl"))
    return Path(hits[0]) if hits else None


def read_session(path):
    """Skills loaded (in order), tool calls by name, the final text, and the list-price cost."""
    skills, tools, cost, final = [], {}, 0.0, ""
    if not path:
        return skills, tools, cost, final
    for line in path.read_text().splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("type") == "message":
            m = r["message"]
            for c in m.get("toolCalls") or []:
                name = c.get("name") or (c.get("function") or {}).get("name")
                tools[name] = tools.get(name, 0) + 1
                if name == "skill":
                    args = c.get("arguments") or (c.get("function") or {}).get("arguments") or "{}"
                    try:
                        a = json.loads(args) if isinstance(args, str) else args
                    except ValueError:
                        a = {}
                    skills.append(str(a.get("name", "?")).lower())
            if m.get("role") == "assistant" and m.get("content"):
                final = m["content"]
            # kurtkode's skill router loads a skill in a note after the request
            if m.get("contextNote") and (h := re.match(r'\[kurtkode: the skill router loaded the "([a-z0-9-]+)" skill', m.get("content", ""))):
                skills.append(h.group(1))
        elif r.get("type") == "cost":
            c = r["cost"]
            cost += c.get("charged") or (c.get("listPrice") or {}).get("total") or 0.0
    return skills, tools, cost, final


def first_tools(path, n=4):
    """The first n tool calls' names, in order (what the model did before or instead of loading a skill)."""
    out = []
    if not path:
        return out
    for line in path.read_text().splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("type") == "message":
            for c in r["message"].get("toolCalls") or []:
                out.append(c.get("name"))
    return out[:n]


def run_kk(project, prompt, model, mode, max_steps, timeout, subagents=False, builtin=False):
    cmd = [str(KK), "-p", prompt, "-m", model, "--mode", mode, "--no-mcp", "--max-steps", str(max_steps),
           "--output", "json", "-C", str(project)] + ([] if builtin else NO_BUILTIN_FLAG) + ROUTER_FLAG
    if not subagents:
        cmd.append("--no-subagents")
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        out, err = p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        out, err = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), "timeout"
    secs = time.time() - t0
    try:
        j = json.loads(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        j = {"error": (err or out)[-800:]}
    return j, secs


JUDGE_PROMPT = """You are grading how a coding agent did a task. The task, then the agent's transcript, are below (stdin).
Grade each criterion 0 (not met), 1 (partly), or 2 (fully met), from evidence in the transcript only.
Reply with ONLY a JSON object: {"scores": [n, ...], "notes": "one sentence"} with one score per criterion, in order.

Criteria:
"""


def judge(sid, task, judge_model, work):
    exp = subprocess.run([str(KK), "export", sid, "--format", "markdown"], capture_output=True, text=True, timeout=60).stdout
    exp = exp[-60000:]
    crit = "\n".join(f"{i+1}. {c}" for i, c in enumerate(task["rubric"]))
    d = work / f"kkskill-judge-{uuid.uuid4().hex[:6]}"
    d.mkdir()
    cmd = [str(KK), "-p", JUDGE_PROMPT + crit, "-m", judge_model, "--mode", "plan", "--no-mcp", "--no-subagents",
           "--max-steps", "2", "--output", "json", "-C", str(d)] + NO_BUILTIN_FLAG
    p = subprocess.run(cmd, input=f"TASK:\n{task['prompt']}\n\nTRANSCRIPT:\n{exp}", capture_output=True, text=True, timeout=300)
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1]).get("result", "")
        m = re.search(r"\{.*\}", res, re.S)
        g = json.loads(m.group(0))
        scores = [int(s) for s in g["scores"]][: len(task["rubric"])]
        return {"scores": scores, "rubric_pct": sum(scores) / (2 * len(task["rubric"])), "notes": g.get("notes", ""),
                "judge_session": json.loads(p.stdout.strip().splitlines()[-1]).get("session")}
    except Exception as e:  # a judge that fails to answer is recorded, not fatal
        return {"error": f"{type(e).__name__}: {p.stdout[-300:]}"}


def load_cases(lib, only):
    cases = []
    for f in sorted(glob.glob(str(CASES / "*" / "cases.json"))):
        skill = Path(f).parent.name
        if only and skill not in only:
            continue
        c = json.loads(Path(f).read_text())
        cases.append((skill, Path(f).parent, c))
    return cases


def trigger_jobs(cases):
    for skill, _, c in cases:
        t = c.get("triggers", {})
        for i, p in enumerate(t.get("should", [])):
            yield {"kind": "trigger", "skill": skill, "expect": True, "case": f"should{i}", "prompt": p}
        for i, p in enumerate(t.get("should_not", [])):
            yield {"kind": "trigger", "skill": skill, "expect": False, "case": f"not{i}", "prompt": p}


def task_jobs(cases, arms):
    for skill, tdir, c in cases:
        for t in c.get("tasks", []):
            for arm in arms:
                yield {"kind": "task", "skill": skill, "case": t["id"], "arm": arm, "task": t, "tdir": str(tdir)}


def run_job(job, a, work):
    lib = Path(a.library)
    if job["kind"] == "trigger":
        proj = make_project(NEUTRAL, work, "trig", None if BUILTIN else lib)
        j, secs = run_kk(proj, job["prompt"], a.model, "plan", a.trigger_steps, a.timeout, builtin=BUILTIN)
        sid = j.get("session")
        skills, tools, cost, final = read_session(session_file(sid) if sid else None)
        loaded = job["skill"] in skills
        return {**{k: job[k] for k in ("kind", "skill", "case", "expect", "prompt")}, "model": a.model,
                "loaded": skills, "hit": loaded == job["expect"], "secs": round(secs, 1), "cost": cost, "tools": tools,
                "first_tools": first_tools(session_file(sid) if sid else None), "stop": j.get("stop"),
                "session": sid, "error": j.get("error"), "project": str(proj)}
    t = job["task"]
    fixture = (Path(job["tdir"]) / t["fixture"]).resolve()
    # baseline: no skills; skills: the whole library, found by the model; forced: the library, and the run is told to
    # load this skill (content without triggering); control: only an irrelevant skill of similar length, force-loaded
    # (what loading any skill costs)
    library = {"skills": lib, "forced": lib, "baseline": None, "control": None}[job["arm"]]
    if BUILTIN:
        library = None   # the skills come with kurtkode
    uses_builtin = BUILTIN and job["arm"] in ("skills", "forced")
    proj = make_project(fixture, work, f"task-{job['case']}-{job['arm']}", library)
    prompt = t["prompt"]
    if job["arm"] == "control":
        shutil.copytree(CONTROL, proj / ".agents" / "skills" / "house-notes")
        with open(proj / ".git" / "info" / "exclude", "a") as f:
            f.write("\n.agents/\n")
    if job["arm"] in ("forced", "control"):
        name = job["skill"] if job["arm"] == "forced" else "house-notes"
        prompt = f"Load the skill \"{name}\" with the skill tool and follow it.\n\n{prompt}"
    j, secs = run_kk(proj, prompt, a.model, "auto", t.get("max_steps", a.task_steps), a.timeout, builtin=uses_builtin)
    sid = j.get("session")
    skills, tools, cost, final = read_session(session_file(sid) if sid else None)
    rc, out = sh(t["check"], proj, timeout=300, env={"CASE_DIR": job["tdir"]})
    rec = {"kind": "task", "skill": job["skill"], "case": job["case"], "arm": job["arm"], "model": a.model,
           "pass": rc == 0, "check_output": out[-600:], "loaded": skills, "tools": tools, "secs": round(secs, 1),
           "cost": cost, "session": sid, "stop": j.get("stop"), "error": j.get("error"), "project": str(proj)}
    if t.get("rubric") and sid and a.judge:
        rec["judge"] = judge(sid, t, a.judge, work)
    return rec


def trash_sessions(results):
    trash = Path.home() / ".Trash"
    for r in results:
        for key in ("session",):
            sid = r.get(key)
            f = session_file(sid) if sid else None
            if f:
                folder = f.parent
                if folder.name.startswith("kkskill-") and folder.exists():
                    shutil.move(str(folder), trash / f"{folder.name}-{uuid.uuid4().hex[:4]}")
        js = (r.get("judge") or {}).get("judge_session")
        f = session_file(js) if js else None
        if f and f.parent.name.startswith("kkskill-") and f.parent.exists():
            shutil.move(str(f.parent), trash / f"{f.parent.name}-{uuid.uuid4().hex[:4]}")


def report(path):
    rows = [json.loads(l) for l in open(path)]
    trig = [r for r in rows if r["kind"] == "trigger"]
    if trig:
        print("TRIGGERS  skill  recall(should load)  specificity(near misses not loaded)  wrong-skill loads")
        by = {}
        for r in trig:
            by.setdefault(r["skill"], []).append(r)
        for s, rs in sorted(by.items()):
            sh_ = [r for r in rs if r["expect"]]
            no = [r for r in rs if not r["expect"]]
            rec = sum(r["hit"] for r in sh_)
            spec = sum(r["hit"] for r in no)
            other = sum(1 for r in sh_ if r["loaded"] and s not in r["loaded"])
            print(f"  {s:32s} {rec}/{len(sh_)}  {spec}/{len(no)}  {other}")
        tot = len(trig)
        print(f"  overall hit rate {sum(r['hit'] for r in trig)}/{tot}; errors {sum(1 for r in trig if r.get('error'))}")
    tasks = [r for r in rows if r["kind"] == "task"]
    if tasks:
        print("\nTASKS  skill/case  arm  pass  rubric%  loaded-own-skill  steps(tool calls)  cost  secs")
        for r in sorted(tasks, key=lambda r: (r["skill"], r["case"], r["arm"])):
            jd = r.get("judge") or {}
            rp = f"{jd['rubric_pct']*100:.0f}" if "rubric_pct" in jd else ("err" if jd else "-")
            print(f"  {r['skill']+'/'+r['case']:44s} {r['arm']:9s} {'PASS' if r['pass'] else 'fail'}  {rp:>4s}  "
                  f"{'yes' if r['skill'] in r['loaded'] else 'no ':3s}  {sum((r.get('tools') or {}).values()):3d}  "
                  f"${r['cost']:.3f}  {r['secs']:.0f}" + (f"  ERR {str(r['error'])[:60]}" if r.get("error") else ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["trigger", "task"], default="task")
    ap.add_argument("--model", default="Google Gemini:gemini-3.6-flash")
    ap.add_argument("--judge", default=None, help="endpoint:model for rubric grading (off when omitted)")
    ap.add_argument("--library", default=str(LIB))
    ap.add_argument("--skills", nargs="*", help="only these skills' cases")
    ap.add_argument("--cases", nargs="*", help="only these case ids")
    ap.add_argument("--arms", default="skills,baseline", help="skills,baseline,forced")
    ap.add_argument("--trials", type=int, default=1)
    ap.add_argument("--parallel", type=int, default=4)
    ap.add_argument("--trigger-steps", type=int, default=3)
    ap.add_argument("--task-steps", type=int, default=40)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--out", default=None)
    ap.add_argument("--work", default=os.environ.get("SKILLEVAL_WORK", str(HERE / "runs")))
    ap.add_argument("--keep-sessions", action="store_true")
    ap.add_argument("--report", default=None)
    ap.add_argument("--agents-md", default=None, help="copy this file into each project that has the library, as AGENTS.md")
    ap.add_argument("--builtin", action="store_true",
                    help="kurtkode's default setup: its built-in skills and prompt line, nothing installed in the project")
    ap.add_argument("--kk", default=None, help="the kurtkode binary (default $KK or AgentCore/.build/release/kurtkode)")
    ap.add_argument("--router", choices=["auto", "on", "off"], default=None, help="kurtkode's --skill-router for the agent's runs")
    a = ap.parse_args()
    global AGENTS_MD, BUILTIN, NO_BUILTIN_FLAG, KK, ROUTER_FLAG
    AGENTS_MD = a.agents_md and str(Path(a.agents_md).resolve())
    if a.kk:
        KK = Path(a.kk)
    BUILTIN = a.builtin
    has_builtin = "--no-builtin-skills" in subprocess.run([str(KK), "--help"], capture_output=True, text=True).stdout
    NO_BUILTIN_FLAG = ["--no-builtin-skills"] if has_builtin else []
    help_text = subprocess.run([str(KK), "--help"], capture_output=True, text=True).stdout
    if a.router:
        if "--skill-router" not in help_text:
            sys.exit(f"{KK} has no skill router")
        ROUTER_FLAG = ["--skill-router", a.router]
    elif "--skill-router" in help_text:
        ROUTER_FLAG = ["--skill-router", "off"]   # measure what was asked for, not the router, unless --router
    if BUILTIN and not has_builtin:
        sys.exit(f"{KK} has no built-in skills (no --no-builtin-skills option)")
    if a.report:
        return report(a.report)
    work = Path(a.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    cases = load_cases(Path(a.library), set(a.skills or []))
    jobs = list(trigger_jobs(cases)) if a.mode == "trigger" else list(task_jobs(cases, a.arms.split(",")))
    if a.cases:
        jobs = [j for j in jobs if j["case"] in a.cases]
    jobs = [j for j in jobs for _ in range(a.trials)]
    out = Path(a.out or HERE / "results" / f"{a.mode}-{time.strftime('%Y%m%d-%H%M%S')}.jsonl")
    out.parent.mkdir(parents=True, exist_ok=True)
    print(f"{len(jobs)} runs on {a.model} → {out}", flush=True)
    results = []
    with cf.ThreadPoolExecutor(a.parallel) as ex, open(out, "a") as f:
        futs = {ex.submit(run_job, j, a, work): j for j in jobs}
        for fut in cf.as_completed(futs):
            try:
                r = fut.result()
            except Exception as e:
                j = futs[fut]
                r = {"kind": j["kind"], "skill": j["skill"], "case": j["case"], "error": repr(e), "hit": False,
                     "pass": False, "loaded": [], "expect": j.get("expect"), "arm": j.get("arm"), "cost": 0, "secs": 0}
            results.append(r)
            f.write(json.dumps(r) + "\n")
            f.flush()
            tag = r.get("arm") or ("should" if r.get("expect") else "not")
            ok = r.get("hit") if r["kind"] == "trigger" else r.get("pass")
            print(f"  {r['skill']}/{r['case']} {tag}: {'ok' if ok else 'MISS'} loaded={r.get('loaded')} "
                  f"{r.get('secs')}s" + (f" ERR {str(r.get('error'))[:80]}" if r.get("error") else ""), flush=True)
    if not a.keep_sessions:
        trash_sessions(results)
    report(out)


if __name__ == "__main__":
    sys.exit(main())
