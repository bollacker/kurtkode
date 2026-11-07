#!/usr/bin/env python3
"""Phase 0 spike: probe LM Studio's OpenAI-compatible API for the behaviors kurtkode depends on.

Stdlib only. Usage: python3 toolcall_spike.py MODEL [MODEL ...] [--trials N]

Probes per model:
  stream   - plain streaming chat: chunk fields, reasoning field name, usage in final chunk
  single   - one forced-choice tool call (non-streaming): is tool_calls well-formed?
  sstream  - same, streaming: do tool-call deltas assemble into valid JSON?
  agent    - multi-step loop over a fake filesystem (list_dir/read_file/edit_file);
             success = the model makes the correct edit and stops. Repeated --trials times.
"""
import json, os, sys, time, urllib.request

BASE = "http://localhost:1234"

TOOLS = [
    {"type": "function", "function": {
        "name": "list_dir", "description": "List files in a directory of the project.",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "read_file", "description": "Read a text file of the project.",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "edit_file",
        "description": "Replace the exact text old_string with new_string in a file. old_string must occur exactly once.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "old_string": {"type": "string"}, "new_string": {"type": "string"}},
            "required": ["path", "old_string", "new_string"]}}},
]

FAKE_FS_INIT = {
    "README.md": "# calc\nA tiny calculator library.\n",
    "src/calc.py": "def add(a, b):\n    return a + b\n\n\ndef sub(a, b):\n    return a + b\n",
    "tests/test_calc.py": "from src.calc import add, sub\n\n\ndef test_sub():\n    assert sub(5, 3) == 2\n",
}

SYSTEM_BASE = ("You are a coding agent working in a project directory. Use the tools to inspect and change files. "
          "When the task is complete, reply with a one-sentence summary and do not call any more tools.")
SYSTEM_STRICT = SYSTEM_BASE + (
    " Tool results appear in the conversation above; read them instead of repeating a call you already made."
    " Work efficiently: once you know which file matters, read it, then edit it. Include enough surrounding"
    " lines in old_string to make it unique.")
VARIANT = os.environ.get("VARIANT", "base")   # base | strict | framed | both
SYSTEM = SYSTEM_STRICT if VARIANT in ("strict", "both") else SYSTEM_BASE
FRAMED = VARIANT in ("framed", "both")
MAX_STEPS = int(os.environ.get("STEPS", "10"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "4096"))       # per turn, reasoning included
TURN_TIMEOUT = float(os.environ.get("TURN_TIMEOUT", "180"))  # wall-clock seconds per turn
SKIP_PROBES = os.environ.get("SKIP_PROBES") == "1"


class TurnTimeout(Exception):
    pass
TASK = "The test in tests/test_calc.py fails. Find the bug in the source and fix it."


def post(path, body, stream=False):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, timeout=600)
    if not stream:
        return json.loads(resp.read())
    def events():
        try:
            for raw in resp:
                line = raw.decode().strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    return
                yield json.loads(data)
        finally:
            resp.close()  # closing the connection makes LM Studio stop generating
    return events()


def probe_stream(model):
    t0 = time.time()
    fields, usage, reasoning_chars, content, ttft = set(), None, 0, "", None
    for ev in post("/v1/chat/completions", {
            "model": model, "stream": True, "stream_options": {"include_usage": True},
            "messages": [{"role": "user", "content": "In two sentences, what is a closure in programming?"}]},
            stream=True):
        if ev.get("usage"):
            usage = ev["usage"]
        for ch in ev.get("choices", []):
            d = ch.get("delta", {})
            fields |= set(d.keys())
            if d.get("content"):
                ttft = ttft or time.time() - t0
                content += d["content"]
            for k in ("reasoning_content", "reasoning"):
                if d.get(k):
                    reasoning_chars += len(d[k])
    return {"delta_fields": sorted(fields), "usage": usage, "reasoning_chars": reasoning_chars,
            "ttft_s": round(ttft or -1, 2), "total_s": round(time.time() - t0, 2), "content": content[:160]}


def probe_single(model):
    r = post("/v1/chat/completions", {
        "model": model, "tools": TOOLS,
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": "Show me what is in the src directory."}]})
    msg = r["choices"][0]["message"]
    calls = msg.get("tool_calls") or []
    ok = bool(calls) and calls[0]["function"]["name"] == "list_dir"
    args = None
    if calls:
        try:
            args = json.loads(calls[0]["function"]["arguments"])
        except Exception as e:
            args = f"BAD JSON: {e}"
    return {"ok": ok, "finish": r["choices"][0].get("finish_reason"), "args": args,
            "content": (msg.get("content") or "")[:120]}


def stream_turn(model, messages):
    """One streamed assistant turn; returns (content, tool_calls, usage, finish_reason).
    Assembles tool-call deltas by index. Raises TurnTimeout after TURN_TIMEOUT seconds."""
    content, calls, usage, finish, t0 = "", {}, None, None, time.time()
    stream = post("/v1/chat/completions", {
            "model": model, "tools": TOOLS, "stream": True, "stream_options": {"include_usage": True},
            "max_tokens": MAX_TOKENS, "messages": messages}, stream=True)
    for ev in stream:
        if time.time() - t0 > TURN_TIMEOUT:
            stream.close()
            raise TurnTimeout(f"turn exceeded {TURN_TIMEOUT:.0f}s")
        if ev.get("usage"):
            usage = ev["usage"]
        for ch in ev.get("choices", []):
            finish = ch.get("finish_reason") or finish
            d = ch.get("delta", {})
            content += d.get("content") or ""
            for tc in d.get("tool_calls") or []:
                c = calls.setdefault(tc.get("index", 0), {"id": "", "name": "", "arguments": ""})
                c["id"] = tc.get("id") or c["id"]
                fn = tc.get("function") or {}
                c["name"] += fn.get("name") or ""
                c["arguments"] += fn.get("arguments") or ""
    return content, [calls[i] for i in sorted(calls)], usage, finish


def probe_sstream(model):
    content, calls, usage, _ = stream_turn(model, [{"role": "system", "content": SYSTEM},
                                                {"role": "user", "content": "Read the file README.md."}])
    parsed = []
    for c in calls:
        try:
            parsed.append((c["name"], json.loads(c["arguments"])))
        except Exception as e:
            parsed.append((c["name"], f"BAD JSON: {c['arguments']!r} ({e})"))
    ok = len(parsed) >= 1 and parsed[0][0] == "read_file" and isinstance(parsed[0][1], dict)
    return {"ok": ok, "calls": parsed, "usage": usage}


def run_tool(fs, name, args):
    if name == "list_dir":
        p = args.get("path", ".").strip("/").removeprefix("./")
        p = "" if p in ("", ".") else p + "/"
        names = sorted({k[len(p):].split("/")[0] for k in fs if k.startswith(p)})
        return "\n".join(names) or f"error: no such directory {args.get('path')}"
    if name == "read_file":
        p = args.get("path", "").removeprefix("./")
        return fs.get(p, f"error: no such file {p}")
    if name == "edit_file":
        p = args.get("path", "").removeprefix("./")
        if p not in fs:
            return f"error: no such file {p}"
        n = fs[p].count(args.get("old_string", ""))
        if n != 1:
            return f"error: old_string occurs {n} times; it must occur exactly once"
        fs[p] = fs[p].replace(args["old_string"], args["new_string"])
        return "ok"
    return f"error: unknown tool {name}"


def probe_agent(model, max_steps=None):
    max_steps = max_steps or MAX_STEPS
    fs = dict(FAKE_FS_INIT)
    msgs = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": TASK}]
    trace, errors, outcome = [], 0, "step_cap"
    content, calls, usage = "", [], None
    for _ in range(max_steps):
        try:
            content, calls, usage, finish = stream_turn(model, msgs)
        except TurnTimeout as e:
            outcome, calls = "turn_timeout", ["?"]
            trace.append(f"TIMEOUT: {e}")
            break
        if finish == "length":
            trace.append(f"TRUNCATED at max_tokens={MAX_TOKENS} (usage={usage})")
            if not calls:
                outcome, calls = "truncated", ["?"]
                break
        if not calls:
            outcome = "stopped"
            break
        msgs.append({"role": "assistant", "content": content or None,
                     "tool_calls": [{"id": c["id"] or f"call_{i}", "type": "function",
                                     "function": {"name": c["name"], "arguments": c["arguments"]}}
                                    for i, c in enumerate(calls)]})
        for i, c in enumerate(calls):
            try:
                args = json.loads(c["arguments"] or "{}")
                out = run_tool(fs, c["name"], args)
            except json.JSONDecodeError:
                out, errors = "error: arguments were not valid JSON", errors + 1
            if out.startswith("error"):
                errors += 1
            trace.append(f"{c['name']}({c['arguments'][:60]}) -> {out[:40]!r}")
            body = f"[{c['name']} {c['arguments']}]\n{out}" if FRAMED else out
            msgs.append({"role": "tool", "tool_call_id": c["id"] or f"call_{i}", "content": body})
    fixed = "return a - b" in fs["src/calc.py"] and "return a + b" in fs["src/calc.py"]
    return {"ok": fixed and outcome == "stopped", "outcome": outcome, "fixed": fixed, "stopped": outcome == "stopped", "steps": len(trace),
            "tool_errors": errors, "prompt_tokens_last": (usage or {}).get("prompt_tokens"),
            "final": (content or "")[:120], "trace": trace}


def main():
    args = sys.argv[1:]
    trials = 3
    if "--trials" in args:
        i = args.index("--trials"); trials = int(args[i + 1]); del args[i:i + 2]
    report = {}
    for model in args:
        print(f"\n===== {model} =====", flush=True)
        r = {}
        probes = () if SKIP_PROBES else (("stream", probe_stream), ("single", probe_single), ("sstream", probe_sstream))
        for name, fn in probes:
            t = time.time()
            try:
                r[name] = fn(model)
            except Exception as e:
                r[name] = {"ok": False, "exception": repr(e)}
            print(f"-- {name} ({time.time() - t:.1f}s): {json.dumps(r[name])}", flush=True)
        r["agent"] = []
        for k in range(trials):
            t = time.time()
            try:
                a = probe_agent(model)
            except Exception as e:
                a = {"ok": False, "exception": repr(e)}
            a["secs"] = round(time.time() - t, 1)
            r["agent"].append(a)
            print(f"-- agent trial {k + 1} ({a['secs']}s): ok={a.get('ok')} outcome={a.get('outcome')} fixed={a.get('fixed')} "
                  f"stopped={a.get('stopped')} steps={a.get('steps')} errors={a.get('tool_errors')}", flush=True)
            for line in a.get("trace", []):
                print("     ", line)
            print("      final:", a.get("final") or a.get("exception"), flush=True)
        report[model] = r
    with open(os.environ.get("OUT") or f"spike_results_{VARIANT}.json", "w") as f:
        json.dump({"variant": VARIANT, "steps": MAX_STEPS, "max_tokens": MAX_TOKENS, "report": report}, f, indent=2)
    print("\nwrote spike_results.json")


if __name__ == "__main__":
    main()
