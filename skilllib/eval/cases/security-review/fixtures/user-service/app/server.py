"""HTTP API for the user service."""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, unquote, urlparse

from app import db, files

CONN = db.connect(os.environ.get("USERS_DB", ":memory:"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        ctype = "application/json"
        try:
            if url.path == "/users":
                body = json.dumps(db.list_users(CONN, q.get("sort", "name"), q.get("limit", 50))).encode()
            elif url.path == "/search":
                body = json.dumps(db.search_users(CONN, q.get("q", ""))).encode()
            elif url.path.startswith("/reports/"):
                body, ctype = files.read_report(unquote(url.path[len("/reports/"):])), "text/plain"
            elif url.path.startswith("/avatars/"):
                with open(files.avatar_path(url.path[len("/avatars/"):]), "rb") as f:
                    body, ctype = f.read(), "image/png"
            else:
                self.send_error(404)
                return
        except (ValueError, OSError):
            self.send_error(400)
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    HTTPServer(("", 8080), Handler).serve_forever()
