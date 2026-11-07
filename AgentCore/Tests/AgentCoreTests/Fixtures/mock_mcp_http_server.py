#!/usr/bin/env python3
"""A Streamable HTTP MCP server for kurtkode's tests (standard library only). Prints "PORT <n>" when ready.

Needs "Authorization: Bearer secret-token". initialize returns an Mcp-Session-Id that later requests must send.
tools/list answers as JSON; tools/call answers as an SSE stream with a log notification first. A GET opens a
stream that sends notifications/tools/list_changed. The tool "expire" ends the session (later requests: 404).
"""
import json, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

state = {"session": "sess-1", "expired": False, "deleted": False, "seen_version": None}
TOOLS = [
    {"name": "echo", "description": "Echo the text", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}},
    {"name": "headers", "description": "Report the MCP headers it saw", "inputSchema": {"type": "object"}},
    {"name": "expire", "description": "End the session", "inputSchema": {"type": "object"}},
    {"name": "deleted", "description": "Whether the client ended the session", "inputSchema": {"type": "object"}},
]

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def reply(self, status, body=b"", ctype="application/json", headers=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items(): self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        if self.headers.get("Authorization") != "Bearer secret-token":
            self.reply(401, b'{"error":"unauthorized"}')
            return False
        return True

    def session_ok(self):
        if state["expired"]:
            self.reply(404, b'{"error":"session not found"}')
            return False
        if self.headers.get("Mcp-Session-Id") != state["session"]:
            self.reply(400, b'{"error":"missing session"}')
            return False
        return True

    def do_POST(self):
        # Read the body first, even when refusing: on a kept-alive connection it would be parsed as the next request.
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        # /cross redirects to another origin (localhost instead of 127.0.0.1), /same to /mcp on this one.
        if self.path == "/cross":
            return self.reply(307, headers={"Location": "http://localhost:%d/mcp" % self.server.server_address[1]})
        if self.path == "/same":
            return self.reply(307, headers={"Location": "/mcp"})
        if not self.authorized(): return
        msg = json.loads(raw)
        method, mid = msg.get("method"), msg.get("id")
        if method == "initialize":
            body = {"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": msg["params"]["protocolVersion"],
                    "capabilities": {"tools": {"listChanged": True}}, "serverInfo": {"name": "mock-http", "version": "2.0"}}}
            return self.reply(200, json.dumps(body).encode(), headers={"Mcp-Session-Id": state["session"]})
        if not self.session_ok(): return
        state["seen_version"] = self.headers.get("MCP-Protocol-Version")
        if mid is None:
            return self.reply(202)
        if method == "tools/list":
            return self.reply(200, json.dumps({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}).encode())
        if method == "tools/call":
            name, args = msg["params"]["name"], msg["params"].get("arguments") or {}
            if name == "echo": text = args.get("text", "")
            elif name == "headers": text = "version=%s session=%s" % (state["seen_version"], self.headers.get("Mcp-Session-Id"))
            elif name == "expire": state["expired"] = True; text = "expired"
            elif name == "deleted": text = "yes" if state["deleted"] else "no"
            else: text = "?"
            events = [{"jsonrpc": "2.0", "method": "notifications/message", "params": {"level": "info", "data": "working"}},
                      {"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": text}]}}]
            body = "".join("event: message\ndata: %s\n\n" % json.dumps(e) for e in events).encode()
            return self.reply(200, body, ctype="text/event-stream")
        self.reply(200, json.dumps({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "no " + method}}).encode())

    def do_GET(self):
        if not self.authorized() or not self.session_ok(): return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        time.sleep(0.3)
        note = {"jsonrpc": "2.0", "method": "notifications/tools/list_changed"}
        try:
            self.wfile.write(("data: %s\n\n" % json.dumps(note)).encode()); self.wfile.flush()
            time.sleep(2)
        except Exception:
            pass

    def do_DELETE(self):
        state["deleted"] = True
        self.reply(200)

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print("PORT %d" % server.server_address[1], flush=True)
threading.Thread(target=server.serve_forever, daemon=True).start()
sys.stdin.read()          # runs until the test closes stdin
