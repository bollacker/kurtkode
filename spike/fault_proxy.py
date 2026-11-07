#!/usr/bin/env python3
"""Fault-injecting proxy for kurtkode evals: forwards chat completions to an upstream OpenAI-compatible
server (LM Studio by default) and drops large write calls the way an OpenRouter provider did, so the
agent loop's recovery can be measured against a real model.

A dropped turn comes back as an empty reply (no content, no tool calls, finish "stop") whose usage still
reports the output tokens, which is what the provider returned.

  python3 spike/fault_proxy.py --port 18080 --arm tailored   # pass kurtkode's nudges through
  python3 spike/fault_proxy.py --port 18080 --arm generic    # rewrite them to the old generic text

Then: kurtkode-eval --endpoint proxy=http://127.0.0.1:18080/v1 --models proxy:qwen/qwen3-coder-30b ...

To imitate OpenRouter's providers: --providers Flaky,Solid --faulty Flaky. Each request goes to the first
provider its `provider.ignore` doesn't exclude, every chunk names it (`"provider": "Flaky"`), and only the
faulty ones drop calls. With every provider ignored, the request fails with 404, as OpenRouter's does.

In front of OpenRouter itself: --upstream https://openrouter.ai/api/v1 --faulty SiliconFlow (and no --providers)
drops large write calls whenever that real provider served them; the request's Authorization header is forwarded.
Stats (drops, nudges seen) go to stderr, one line per event.
"""
import argparse
import json
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GENERIC_NUDGE = ("Your last reply was empty. Continue the task (try a different approach if a "
                 "search found nothing), or give your answer.")
WRITE_TOOLS = {"write_file", "edit_file"}

args = None
lock = threading.Lock()
stats = {"requests": 0, "dropped": 0, "nudges": 0, "rerouted": 0}


def log(event, **kw):
    with lock:
        print(json.dumps({"event": event, **kw, **stats}), file=sys.stderr, flush=True)


def assemble(sse_lines):
    """Tool calls (name, arguments) and usage from buffered SSE lines."""
    calls, usage, model, provider = {}, None, None, None
    for line in sse_lines:
        if not line.startswith(b"data:"):
            continue
        payload = line[5:].strip()
        if payload == b"[DONE]" or not payload:
            continue
        try:
            chunk = json.loads(payload)
        except ValueError:
            continue
        model = chunk.get("model", model)
        provider = chunk.get("provider", provider)
        usage = chunk.get("usage") or usage
        for choice in chunk.get("choices") or []:
            for i, tc in enumerate((choice.get("delta") or {}).get("tool_calls") or []):
                c = calls.setdefault(tc.get("index", i), {"name": "", "arguments": ""})
                fn = tc.get("function") or {}
                c["name"] += fn.get("name") or ""
                c["arguments"] += fn.get("arguments") or ""
    return list(calls.values()), usage, model, provider


def with_provider(raw, provider):
    """Adds "provider" to every JSON chunk of an SSE body."""
    out = []
    for line in raw.splitlines():
        if line.startswith(b"data:") and line[5:].strip() not in (b"", b"[DONE]"):
            try:
                chunk = json.loads(line[5:])
                chunk["provider"] = provider
                line = b"data: " + json.dumps(chunk).encode()
            except ValueError:
                pass
        out.append(line)
    return b"\n".join(out) + b"\n"


def pick_provider(req):
    ignore = {p.lower() for p in ((req.get("provider") or {}).get("ignore") or [])}
    for p in args.providers:
        if p.lower() not in ignore:
            return p
    return None


def empty_reply(model, usage):
    def data(o):
        return b"data: " + json.dumps(o).encode() + b"\n\n"
    out = data({"model": model, "choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}, "finish_reason": None}]})
    out += data({"model": model, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
    out += data({"model": model, "choices": [], "usage": usage or {"prompt_tokens": 0, "completion_tokens": 0}})
    return out + b"data: [DONE]\n\n"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        self.forward(None)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.provider = None
        if self.path.endswith("/chat/completions"):
            req = json.loads(body)
            if args.providers:
                self.provider = pick_provider(req)
                if req.get("provider", {}).get("ignore"):
                    with lock:
                        stats["rerouted"] += 1
                if self.provider is None:
                    log("no_provider", ignore=req["provider"].get("ignore"))
                    msg = json.dumps({"error": {"message": "No endpoints found matching your data policy", "code": 404}}).encode()
                    self.send_response(404)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(msg)))
                    self.end_headers()
                    self.wfile.write(msg)
                    return
                req.pop("provider", None)
            for m in req.get("messages", []):
                if m.get("role") == "user" and str(m.get("content", "")).startswith("Your last reply"):
                    with lock:
                        stats["nudges"] += 1
                    if args.arm == "generic":
                        m["content"] = GENERIC_NUDGE
            body = json.dumps(req).encode()
            with lock:
                stats["requests"] += 1
        self.forward(body)

    def forward(self, body):
        url = args.upstream.rstrip("/") + self.path[len("/v1"):] if self.path.startswith("/v1") else args.upstream + self.path
        headers = {"Content-Type": "application/json"} if body is not None else {}
        if self.headers.get("Authorization"):
            headers["Authorization"] = self.headers["Authorization"]
        request = urllib.request.Request(url, data=body, headers=headers, method="POST" if body is not None else "GET")
        try:
            with urllib.request.urlopen(request, timeout=900) as r:
                status, ctype, raw = r.status, r.headers.get("Content-Type", ""), r.read()
        except urllib.error.HTTPError as e:
            status, ctype, raw = e.code, e.headers.get("Content-Type", ""), e.read()
        if body is not None and status == 200 and self.path.endswith("/chat/completions"):
            calls, usage, model, served = assemble(raw.splitlines())
            if not args.providers:
                self.provider = served          # the real provider (OpenRouter), or None
            big = [c for c in calls if c["name"] in WRITE_TOOLS and len(c["arguments"]) > args.limit]
            faulty = (self.provider in args.faulty) if args.faulty else True
            if big and faulty:
                with lock:
                    stats["dropped"] += 1
                log("dropped", provider=self.provider, tools=[c["name"] for c in calls],
                    bytes=[len(c["arguments"]) for c in calls], completion_tokens=(usage or {}).get("completion_tokens"))
                raw, ctype = empty_reply(model, usage), "text/event-stream"
                if served and not args.providers:
                    raw = with_provider(raw, served)    # a real lost reply still names its provider
            elif big:
                log("delivered", provider=self.provider, bytes=[len(c["arguments"]) for c in calls])
            if self.provider and args.providers:
                raw = with_provider(raw, self.provider)
        self.send_response(status)
        self.send_header("Content-Type", ctype or "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


def main():
    global args
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=18080)
    p.add_argument("--upstream", default="http://127.0.0.1:1234/v1")
    p.add_argument("--arm", choices=["tailored", "generic"], required=True)
    p.add_argument("--limit", type=int, default=300, help="drop write_file/edit_file calls with more argument bytes")
    p.add_argument("--providers", default="", help="provider names to imitate, in OpenRouter's order of choice")
    p.add_argument("--faulty", default="", help="the providers that drop large write calls (default: all)")
    args = p.parse_args()
    args.providers = [x for x in args.providers.split(",") if x]
    args.faulty = set(x for x in args.faulty.split(",") if x) or set(args.providers)
    log("start", arm=args.arm, limit=args.limit, upstream=args.upstream, providers=args.providers, faulty=sorted(args.faulty))
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
