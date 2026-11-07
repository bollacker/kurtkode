#!/usr/bin/env python3
"""An OpenAI-compatible server that streams a fixed reply at a set speed, for measuring the app's UI while a
reply streams (no model needed).

  python3 spike/mock_stream_server.py --port 18090 --text reply.md --tps 55
  open --env KURTKODE_EXTRA_ENDPOINT=Mock=http://127.0.0.1:18090/v1 --env 'KURTKODE_MODEL=Mock|mock' ... kurtkode.app

--tps is tokens per second, with a token taken as 4 characters (Qwen3-Coder on this Mac streams 50-60).
Each request gets the same reply. /v1/models lists one model, "mock". With --bash CMD, a request whose last
message is the user's gets a bash tool call running CMD instead (to measure live command output).
"""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

args = None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_GET(self):
        body = json.dumps({"object": "list", "data": [{"id": "mock", "object": "model"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        last = (body.get("messages") or [{}])[-1].get("role")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        text = open(args.text, encoding="utf-8").read()
        step = 4 * args.tokens_per_chunk
        delay = args.tokens_per_chunk / args.tps

        def send(obj):
            self.wfile.write(("data: " + json.dumps(obj) + "\n\n").encode())
            self.wfile.flush()

        try:
            if args.bash and last == "user":
                call = {"index": 0, "id": "call_mock", "type": "function",
                        "function": {"name": "bash", "arguments": json.dumps({"command": args.bash, "timeout": 600})}}
                send({"model": "mock", "choices": [{"index": 0, "delta": {"tool_calls": [call]}, "finish_reason": None}]})
                send({"model": "mock", "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]})
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()
                return
            for i in range(0, len(text), step):
                send({"model": "mock", "choices": [{"index": 0, "delta": {"content": text[i:i + step]}, "finish_reason": None}]})
                time.sleep(delay)
            send({"model": "mock", "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
            send({"model": "mock", "choices": [], "usage": {"prompt_tokens": 100, "completion_tokens": len(text) // 4}})
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    global args
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=18090)
    p.add_argument("--text", required=True, help="the reply to stream (a Markdown file)")
    p.add_argument("--tps", type=float, default=55, help="tokens per second (4 characters each)")
    p.add_argument("--tokens-per-chunk", type=int, default=1)
    p.add_argument("--bash", help="answer the user's message with a bash tool call running this command")
    args = p.parse_args()
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
