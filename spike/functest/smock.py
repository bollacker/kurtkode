#!/usr/bin/env python3
"""Scripted OpenAI-compatible mock. smock.py PORT STEP [STEP...]; one step per POST, the last repeats.
Steps: NNN[:message] (HTTP error with that body, Retry-After 1) | drop (a chunk, then the connection closes) | lost:PROV  (empty reply, 80 output tokens) | ok:PROV:TEXT | empty (0 tokens) | 429 | 500 | die (exit) | hang
Logs each request's provider prefs and model to stderr."""
import json, sys, os, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
port = int(sys.argv[1]); steps = sys.argv[2:]; n = [0]
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_GET(self):
        b = json.dumps({"object": "list", "data": [{"id": "mock", "object": "model"}, {"id": "mock2", "object": "model"}]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        i = n[0]; n[0] += 1
        step = steps[min(i, len(steps) - 1)]
        print(json.dumps({"req": i, "step": step, "model": body.get("model"), "provider": body.get("provider"), "last": (body.get("messages") or [{}])[-1].get("content", "")[:120] if isinstance((body.get("messages") or [{}])[-1].get("content"), str) else "?"}), file=sys.stderr, flush=True)
        kind, _, rest = step.partition(":")
        if kind.isdigit():
            b = json.dumps({"error": {"message": rest or f"mock {kind}", "code": int(kind)}}).encode()
            self.send_response(int(kind)); self.send_header("Retry-After", "1"); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b); return
        if kind == "die":
            os._exit(0)
        if kind == "drop":
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.send_header("Connection", "close"); self.end_headers()
            self.wfile.write(('data: ' + json.dumps({"model": "mock", "choices": [{"index": 0, "delta": {"content": "Partial answer before the drop"}, "finish_reason": None}]}) + '\n\n').encode()); self.wfile.flush()
            time.sleep(0.5); self.connection.shutdown(2); self.connection.close(); return
        if kind == "hang":
            time.sleep(3600)
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.send_header("Connection", "close"); self.end_headers()
        prov, _, text = rest.partition(":")
        def send(o):
            if prov: o["provider"] = prov
            self.wfile.write(("data: " + json.dumps(o) + "\n\n").encode()); self.wfile.flush()
        m = body.get("model", "mock")
        if kind == "ok":
            for k in range(0, len(text), 8):
                send({"model": m, "choices": [{"index": 0, "delta": {"content": text[k:k+8]}, "finish_reason": None}]}); time.sleep(0.01)
            ct = max(1, len(text) // 4)
        else:
            ct = 80 if kind == "lost" else 0
        send({"model": m, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
        send({"model": m, "choices": [], "usage": {"prompt_tokens": 100, "completion_tokens": ct}})
        self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
