#!/usr/bin/env python3
"""A priced OpenAI-compatible mock for round 4: GET /models lists prices (OpenRouter format); POST chat/completions
plays a script, one step per request (the last repeats), each a JSON object:
  {"text": "...", "bash": "cmd", "tool": "name", "args": {...}, "usage": {...}, "status": 500, "drop": true, "sleep": 2}
Usage defaults to 1000 prompt / 100 completion tokens. Requests are logged to LOG (one JSON line each).
Usage: pmock.py PORT SCRIPT.json LOG
"""
import base64, json, re, sys, time, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(sys.argv[1]); script = json.load(open(sys.argv[2])); log = sys.argv[3]; n = [0]
PRICES = {"data": [{"id": "pm/model", "pricing": {"prompt": "0.000002", "completion": "0.000010",
                                                  "input_cache_read": "0.0000005", "request": "0.001"}},
                   {"id": "pm/other", "pricing": {"prompt": "0.000001", "completion": "0.000002"}}]}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        body = json.dumps(PRICES).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        i = n[0]; n[0] += 1
        step = script[min(i, len(script) - 1)]
        # Images sent, decoded next to the log, so a scenario can look at what really went out.
        seen = re.findall(r"data:(image/[a-z]+);base64,([A-Za-z0-9+/=]+)", json.dumps(req))
        if seen:
            open(log + ".image", "wb").write(base64.b64decode(seen[-1][1]))
        with open(log, "a") as f:
            f.write(json.dumps({"i": i, "path": self.path, "model": req.get("model"), "messages": len(req.get("messages", [])),
                                "max_tokens": req.get("max_tokens"), "step": step, "last": str((req.get("messages") or [{}])[-1].get("content"))[:200000], "users": [str(m.get("content"))[:200] for m in req.get("messages", []) if m.get("role") == "user"]}) + "\n")
        if step.get("sleep"): time.sleep(step["sleep"])
        if step.get("status"):
            body = json.dumps({"error": {"message": step.get("message", "mock error"), "code": step["status"]}}).encode()
            self.send_response(step["status"]); self.send_header("Content-Type", "application/json")
            self.send_header("Retry-After", "1"); self.send_header("Content-Length", str(len(body))); self.end_headers()
            self.wfile.write(body); return
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        m = req.get("model"); rid = "gen-" + uuid.uuid4().hex[:12]
        def send(o):
            self.wfile.write(b"data: " + json.dumps(o).encode() + b"\n\n"); self.wfile.flush()
        def chunk(delta, finish=None):
            send({"id": rid, "model": m, "provider": "MockProv", "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]})
        if step.get("text"):
            for k in range(0, len(step["text"]), 20): chunk({"content": step["text"][k:k+20]})
        if step.get("drop"):
            self.wfile.flush(); return
        calls = []
        if step.get("bash"): calls.append(("bash", {"command": step["bash"]}))
        if step.get("tool"): calls.append((step["tool"], step.get("args", {})))
        for c in step.get("calls", []): calls.append((c[0], c[1]))
        for j, (name, args) in enumerate(calls):
            chunk({"tool_calls": [{"index": j, "id": f"call_{i}_{j}", "type": "function",
                                   "function": {"name": name, "arguments": json.dumps(args)}}]})
        chunk({}, "tool_calls" if calls else "stop")
        u = {"prompt_tokens": 1000, "completion_tokens": 100}
        u.update(step.get("usage", {}))
        send({"id": rid, "model": m, "provider": "MockProv", "choices": [], "usage": u})
        self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()

ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
