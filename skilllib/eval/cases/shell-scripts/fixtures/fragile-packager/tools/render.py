#!/usr/bin/env python3
"""Render a note in a small Markdown subset (# headings, paragraphs, ``` code blocks) to HTML on stdout.
Usage: render.py NOTE.md   Exit 1 (message on stderr) if the note is malformed."""
import html, sys

path = sys.argv[1]
out, para, code = [], [], None
for n, line in enumerate(open(path, encoding="utf-8"), 1):
    line = line.rstrip("\n")
    if line.startswith("```"):
        if code is None:
            code = []
        else:
            out.append("<pre><code>" + html.escape("\n".join(code)) + "</code></pre>")
            code = None
        continue
    if code is not None:
        code.append(line)
    elif line.startswith("#"):
        level = len(line) - len(line.lstrip("#"))
        out.append(f"<h{level}>{html.escape(line[level:].strip())}</h{level}>")
    elif line.strip():
        para.append(html.escape(line.strip()))
    elif para:
        out.append("<p>" + " ".join(para) + "</p>")
        para = []
if code is not None:
    print(f"render.py: {path}: unclosed code block", file=sys.stderr)
    sys.exit(1)
if para:
    out.append("<p>" + " ".join(para) + "</p>")
print("<!doctype html>\n<meta charset=utf-8>\n" + "\n".join(out))
