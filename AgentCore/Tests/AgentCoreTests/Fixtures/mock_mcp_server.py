#!/usr/bin/env python3
"""A small MCP server over stdio for kurtkode's tests (standard library only).

Tools come in two pages (tests pagination). On `notifications/initialized` it pings the client (tests
server-to-client requests). `change` adds a tool and sends `notifications/tools/list_changed`.
"""
import json, sys, time

pong = {"got": False}
extra = {"on": False}
PAGE1 = [
    {"name": "echo", "description": "Echo the text back", "annotations": {"readOnlyHint": True}, "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}},
    {"name": "add", "description": "Add two numbers", "inputSchema": {"type": "object", "properties": {"a": {"type": "number"}, "b": {"type": "number"}}}},
]
PAGE2 = [
    {"name": "fail", "description": "Always reports an error", "inputSchema": {"type": "object"}},
    {"name": "picture", "description": "Returns an image", "inputSchema": {"type": "object"}},
    {"name": "slow", "description": "Takes 5 seconds", "inputSchema": {"type": "object"}},
    {"name": "pinged", "description": "Whether the client answered the ping", "inputSchema": {"type": "object"}},
    {"name": "change", "description": "Adds a tool", "inputSchema": {"type": "object"}},
    {"name": "crash", "description": "Exits", "inputSchema": {"type": "object"}},
]

def send(o):
    sys.stdout.write(json.dumps(o) + "\n")
    sys.stdout.flush()

def text(s, error=False):
    return {"content": [{"type": "text", "text": s}], "isError": error}

print("mock server starting", file=sys.stderr, flush=True)
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    method, mid = msg.get("method"), msg.get("id")
    if method is None:                      # a response to our ping
        if mid == "srv-ping" and "result" in msg:
            pong["got"] = True
        continue
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": msg["params"]["protocolVersion"],
              "capabilities": {"tools": {"listChanged": True}, "resources": {}}, "serverInfo": {"name": "mock", "version": "1.0"},
              "instructions": "Prefer echo for simple checks."}})
    elif method == "notifications/initialized":
        send({"jsonrpc": "2.0", "id": "srv-ping", "method": "ping"})
    elif method == "resources/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"resources": [{"uri": "mock://notes", "name": "Notes", "description": "Team notes", "mimeType": "text/plain"}]}})
    elif method == "resources/read":
        send({"jsonrpc": "2.0", "id": mid, "result": {"contents": [{"uri": "mock://notes", "text": "the notes say hello"}]}})
    elif method == "tools/list":
        cursor = (msg.get("params") or {}).get("cursor")
        if cursor is None:
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": PAGE1, "nextCursor": "page2"}})
        else:
            tools = PAGE2 + ([{"name": "extra", "description": "Added later", "inputSchema": {"type": "object"}}] if extra["on"] else [])
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": tools}})
    elif method == "tools/call":
        name, args = msg["params"]["name"], msg["params"].get("arguments") or {}
        if name == "echo":
            send({"jsonrpc": "2.0", "id": mid, "result": text(args.get("text", ""))})
        elif name == "add":
            send({"jsonrpc": "2.0", "id": mid, "result": text(str(args.get("a", 0) + args.get("b", 0)))})
        elif name == "fail":
            send({"jsonrpc": "2.0", "id": mid, "result": text("something went wrong", error=True)})
        elif name == "picture":
            send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "a chart:"},
                  {"type": "image", "data": "iVBORw0KGgo=", "mimeType": "image/png"}]}})
        elif name == "slow":
            time.sleep(5)
            send({"jsonrpc": "2.0", "id": mid, "result": text("done")})
        elif name == "pinged":
            send({"jsonrpc": "2.0", "id": mid, "result": text("yes" if pong["got"] else "no")})
        elif name == "change":
            extra["on"] = True
            send({"jsonrpc": "2.0", "method": "notifications/tools/list_changed"})
            send({"jsonrpc": "2.0", "id": mid, "result": text("changed")})
        elif name == "crash":
            print("fatal: crashing on purpose", file=sys.stderr, flush=True)
            sys.exit(3)
        else:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": "unknown tool " + name}})
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "no " + method}})
