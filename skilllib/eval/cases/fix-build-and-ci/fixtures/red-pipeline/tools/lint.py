#!/usr/bin/env python3
"""Small project linter. Usage: lint.py PATH...  Reads lint.cfg. Exit 1 if any E rule fires.
E201 local variable assigned but never used   E202 import never used
W301 public function without a docstring      W302 line longer than max_line
A line ending in '# lint: ignore' is not checked."""
import ast, os, sys

cfg = {"disable": "", "max_line": "100"}
for line in open(os.path.join(os.path.dirname(__file__), "..", "lint.cfg")):
    if "=" in line and not line.lstrip().startswith("#"):
        k, v = line.split("=", 1)
        cfg[k.strip()] = v.strip()
disabled = {r.strip() for r in cfg["disable"].split(",") if r.strip()}
findings = []


def report(path, lineno, rule, msg, src):
    if rule not in disabled and not src[lineno - 1].rstrip().endswith("# lint: ignore"):
        findings.append(f"{path}:{lineno}: {rule} {msg}")


def check(path):
    text = open(path).read()
    src = text.splitlines() or [""]
    tree = ast.parse(text, path)
    loaded = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}
    loaded |= {n.value.id for n in ast.walk(tree) if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name)}
    if not path.endswith("__init__.py"):
        for node in tree.body:
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                for alias in node.names:
                    name = (alias.asname or alias.name).split(".")[0]
                    if name not in loaded:
                        report(path, node.lineno, "E202", f"'{name}' imported but never used", src)
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        if not fn.name.startswith("_") and not ast.get_docstring(fn):
            report(path, fn.lineno, "W301", f"function '{fn.name}' has no docstring", src)
        stored, used = {}, set()
        for n in ast.walk(fn):
            if isinstance(n, ast.Name):
                if isinstance(n.ctx, ast.Store):
                    stored.setdefault(n.id, n.lineno)
                else:
                    used.add(n.id)
        for name, lineno in stored.items():
            if name not in used and not name.startswith("_"):
                report(path, lineno, "E201", f"local variable '{name}' is assigned but never used", src)
    for i, line in enumerate(src, 1):
        if len(line) > int(cfg["max_line"]):
            report(path, i, "W302", f"line too long ({len(line)} > {cfg['max_line']})", src)


for root in sys.argv[1:]:
    for d, _, files in sorted(os.walk(root)):
        for f in sorted(files):
            if f.endswith(".py"):
                check(os.path.join(d, f))
for f in findings:
    print(f)
errors = sum(" E" in f for f in findings)
print(f"lint: {errors} error(s), {len(findings) - errors} warning(s)")
sys.exit(1 if errors else 0)
