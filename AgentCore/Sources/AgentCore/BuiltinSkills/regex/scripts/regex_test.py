#!/usr/bin/env python3
"""Test a regular expression against lines that must match, lines that must not, and expected captures.

Usage: regex_test.py (--pattern PAT | --pattern-file FILE) [--match FILE] [--no-match FILE] [--expect FILE]
                     [--mode search|match|fullmatch] [--flags imsx] [--engine python|node] [--timeout SECS]

  --pattern-file  the pattern is the file's content without the final newline (use it to avoid shell quoting)
  --match         one example per line that must match        (.jsonl: one JSON string per line)
  --no-match      one example per line that must NOT match    (.jsonl: one JSON string per line)
  --expect        JSON lines {"line": "...", "groups": {"name": "value", ...}} -- named groups, or "1", "2", ...
                  for numbered ones; "groups": null means the line must not match. Groups not listed are ignored.
  --mode          search (anywhere in the line, default), match (at the start), fullmatch (the whole line)
  --flags         i = ignore case, m = multiline, s = dot matches newline, x = verbose (python only)
  --engine        python (re) or node (JavaScript RegExp, needs node); patterns differ between flavors
  --timeout       seconds for the whole run (default 10): catches catastrophic backtracking

Plain-text example files keep trailing spaces and "\\r"; only the final "\\n" is removed and empty lines are skipped.
Use .jsonl files when an example needs leading/trailing whitespace made explicit or a newline inside it.

Prints one line per problem:
  MISS   file:N  'line'                          (should match, didn't)
  EXTRA  file:N  'line'  matched 'text'           (should not match, did)
  GROUPS file:N  'line'  got {...} want {...}
then "RESULT pass=P fail=F engine=E mode=M".

Exit codes: 0 = every example behaved, 1 = at least one mismatch (or timeout), 2 = usage error or the pattern
does not compile.
"""
import argparse, json, os, re, subprocess, sys

NODE = r"""
const inp = JSON.parse(require('fs').readFileSync(0, 'utf8'));
let flags = inp.flags.replace(/x/g, '');
let src = inp.mode === 'fullmatch' ? '^(?:' + inp.pattern + ')$' : inp.pattern;
if (inp.mode === 'match') flags += 'y';
let rx;
try { rx = new RegExp(src, flags); }
catch (e) { console.log(JSON.stringify({error: String(e.message)})); process.exit(0); }
const out = inp.lines.map(l => {
  rx.lastIndex = 0;
  const m = rx.exec(l);
  if (!m) return null;
  const g = {};
  m.slice(1).forEach((v, i) => { g[String(i + 1)] = v === undefined ? null : v; });
  if (m.groups) for (const k in m.groups) g[k] = m.groups[k] === undefined ? null : m.groups[k];
  return {text: m[0], groups: g};
});
console.log(JSON.stringify({results: out}));
"""


def py_worker():
    inp = json.load(sys.stdin)
    fl = 0
    for c, f in (("i", re.I), ("m", re.M), ("s", re.S), ("x", re.X)):
        if c in inp["flags"]:
            fl |= f
    try:
        rx = re.compile(inp["pattern"], fl)
    except re.error as e:
        print(json.dumps({"error": str(e)}))
        return 0
    fn = {"search": rx.search, "match": rx.match, "fullmatch": rx.fullmatch}[inp["mode"]]
    out = []
    for line in inp["lines"]:
        m = fn(line)
        if not m:
            out.append(None)
            continue
        g = {str(i): v for i, v in enumerate(m.groups(), 1)}
        g.update(m.groupdict())
        out.append({"text": m.group(0), "groups": g})
    print(json.dumps({"results": out}))
    return 0


def load(path):
    items = []
    with open(path, encoding="utf-8", newline="") as f:
        for n, raw in enumerate(f, 1):
            line = raw[:-1] if raw.endswith("\n") else raw
            if not line.strip("\r"):
                continue
            if path.endswith(".jsonl"):
                v = json.loads(line)
                if isinstance(v, dict):
                    items.append((n, v["line"], v.get("groups")))
                else:
                    items.append((n, v, None))
            else:
                items.append((n, line, None))
    return items


def main():
    if sys.argv[1:] == ["--_worker"]:
        return py_worker()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--pattern")
    src.add_argument("--pattern-file")
    ap.add_argument("--match")
    ap.add_argument("--no-match")
    ap.add_argument("--expect")
    ap.add_argument("--mode", choices=["search", "match", "fullmatch"], default="search")
    ap.add_argument("--flags", default="")
    ap.add_argument("--engine", choices=["python", "node"], default="python")
    ap.add_argument("--timeout", type=float, default=10)
    a = ap.parse_args()
    if not (a.match or a.no_match or a.expect) or set(a.flags) - set("imsx"):
        ap.print_usage(sys.stderr)
        return 2
    pattern = a.pattern
    if a.pattern_file:
        pattern = open(a.pattern_file, encoding="utf-8").read()
        pattern = pattern[:-1] if pattern.endswith("\n") else pattern
    cases = []  # (kind, file, n, line, want_groups)
    try:
        for kind, path in (("match", a.match), ("no-match", a.no_match), ("expect", a.expect)):
            if path:
                cases += [(kind, path, n, line, g) for n, line, g in load(path)]
    except (OSError, ValueError, KeyError) as e:
        print(f"cannot read examples: {e}", file=sys.stderr)
        return 2
    payload = json.dumps({"pattern": pattern, "flags": a.flags, "mode": a.mode, "lines": [c[3] for c in cases]})
    cmd = ["node", "-e", NODE] if a.engine == "node" else [sys.executable, os.path.abspath(__file__), "--_worker"]
    try:
        p = subprocess.run(cmd, input=payload, capture_output=True, text=True, timeout=a.timeout)
    except FileNotFoundError:
        print("node not found", file=sys.stderr)
        return 2
    except subprocess.TimeoutExpired:
        print(f"TIMEOUT after {a.timeout}s: the pattern backtracks catastrophically on some example")
        print(f"RESULT pass=0 fail={len(cases)} engine={a.engine} mode={a.mode}")
        return 1
    try:
        res = json.loads(p.stdout)
    except ValueError:
        print("engine failed: " + (p.stderr or p.stdout)[-300:], file=sys.stderr)
        return 2
    if "error" in res:
        print(f"pattern does not compile ({a.engine}): {res['error']}", file=sys.stderr)
        return 2
    passed = failed = 0
    for (kind, path, n, line, want), got in zip(cases, res["results"]):
        where = f"{os.path.basename(path)}:{n}"
        problem = None
        if kind == "match" and got is None:
            problem = f"MISS   {where}  {line!r}"
        elif kind == "no-match" and got is not None:
            problem = f"EXTRA  {where}  {line!r}  matched {got['text']!r}"
        elif kind == "expect":
            if want is None and got is not None:
                problem = f"EXTRA  {where}  {line!r}  matched {got['text']!r}"
            elif want is not None and got is None:
                problem = f"MISS   {where}  {line!r}"
            elif want is not None:
                sub = {k: got["groups"].get(k) for k in want}
                if sub != want:
                    problem = f"GROUPS {where}  {line!r}  got {sub} want {want}"
        if problem:
            failed += 1
            print(problem)
        else:
            passed += 1
    print(f"RESULT pass={passed} fail={failed} engine={a.engine} mode={a.mode}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
