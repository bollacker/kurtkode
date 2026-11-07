#!/usr/bin/env python3
"""Inventory and apply a mechanical rename across many files, touching only the locations you approved.

Usage:
  codemod.py find NAME [PATH ...] [--max N] [--lookalikes]
      List every whole-word occurrence of NAME under PATHs (default: .), one per line:
        path:line:col  KIND  source line
      KIND is code:def (a definition), code:import, code:attr(<receiver>) (x.NAME), code, string, comment, or doc
      (Markdown/text files). Ends with counts per kind, then the LOOKALIKE identifiers that merely contain NAME
      (NAME_suffix, preNAME) with their counts: a plain text replace would hit them, a whole-word rename won't.
      --lookalikes lists each of those occurrences too.
  codemod.py apply OLD NEW --from SELECTED [--write]
      SELECTED is a copy of find's output with only the lines to change (other text on a line is ignored; lines
      starting with # are skipped). Checks that OLD is still at each path:line:col, then prints a unified diff
      (dry run) or, with --write, changes exactly those locations.

Exit codes:
  find:  0 = no occurrences, 1 = occurrences listed, 2 = usage error
  apply: 0 = every location matched (and was written with --write), 1 = some location no longer holds OLD
         (nothing written), 2 = usage error
Skips .git, node_modules, virtualenvs, build output and binary files. Never writes without --write.
"""
import argparse, difflib, io, os, re, sys, tokenize

SKIP_DIRS = {".git", ".hg", ".svn", "node_modules", ".venv", "venv", "env", "__pycache__", "dist", "build", "target",
             ".tox", ".build", ".next", "vendor", "Pods", ".mypy_cache", ".pytest_cache"}
HASH = {".py", ".pyi", ".sh", ".bash", ".zsh", ".rb", ".pl", ".r", ".yaml", ".yml", ".toml", ".cfg", ".ini", ".conf",
        ".mk", ".cmake", ".ex", ".exs", ".jl", ".nim", ".tf", ".dockerfile", ""}
SLASH = {".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".java", ".kt", ".kts", ".go", ".rs", ".swift", ".c", ".h",
         ".cc", ".cpp", ".hpp", ".cs", ".scala", ".php", ".dart", ".m", ".mm", ".groovy", ".gradle", ".proto", ".css",
         ".scss", ".less", ".json", ".jsonc"}
DOC = {".md", ".markdown", ".txt", ".rst", ".adoc", ".html", ".htm", ".xml", ".csv"}
DEF = re.compile(r"(?:\bdef|\bclass|\bfunction|\bfunc|\bfn|\blet|\bconst|\bvar|\binterface|\btype|\bstruct)\s+$")
IMPORT = re.compile(r"^\s*(?:import\b|from\b.*\bimport\b|use\b|#include\b|export\s+\{|.*\brequire\s*\()")


def kinds_of(text, ext):
    """Per-offset kind: 'c' code, 's' string, 'm' comment, 'd' doc."""
    if ext in DOC:
        return "d" * len(text)
    k = ["c"] * len(text)
    if ext in (".py", ".pyi"):
        try:
            starts = [0]
            for ln in text.splitlines(keepends=True):
                starts.append(starts[-1] + len(ln))
            for t in tokenize.generate_tokens(io.StringIO(text).readline):
                tname = tokenize.tok_name.get(t.type, "")
                kind = "s" if tname == "STRING" or tname.startswith(("FSTRING_", "TSTRING_")) else \
                    "m" if tname == "COMMENT" else None
                if kind:
                    a, b = starts[t.start[0] - 1] + t.start[1], starts[t.end[0] - 1] + t.end[1]
                    k[a:b] = kind * (b - a)
            return "".join(k)
        except (tokenize.TokenError, IndentationError, SyntaxError):
            pass
    i, n = 0, len(text)
    hash_c, slash_c = ext in HASH or ext not in SLASH, ext in SLASH and ext not in (".json",)
    while i < n:
        c = text[i]
        if c in "\"'`":
            j = i + 1
            while j < n and text[j] != c and not (c != "`" and text[j] == "\n"):
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n); k[i:j] = "s" * (j - i); i = j
        elif (slash_c and text.startswith("//", i)) or (hash_c and c == "#"):
            j = text.find("\n", i); j = n if j < 0 else j
            k[i:j] = "m" * (j - i); i = j
        elif slash_c and text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            k[i:j] = "m" * (j - i); i = j
        else:
            i += 1
    return "".join(k)


def files_under(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
            continue
        for d, dirs, files in os.walk(p):
            dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
            for f in sorted(files):
                yield os.path.join(d, f)


def read_text(path):
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        return None
    if b"\0" in data[:4096]:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def find(a):
    name = a.args[0]
    whole = re.compile(r"(?<![\w$])" + re.escape(name) + r"(?![\w$])")
    look = re.compile(r"[\w$]*" + re.escape(name) + r"[\w$]*")
    rows, counts, alike = [], {}, {}
    for path in files_under(a.args[1:] or ["."]):
        text = read_text(path)
        if text is None or name not in text:
            continue
        ext = os.path.splitext(path)[1].lower()
        if os.path.basename(path).lower() in ("makefile", "dockerfile"):
            ext = ""
        kinds = kinds_of(text, ext)
        lines = text.splitlines()
        hits = [(m.start(), m.end(), None) for m in whole.finditer(text)]
        hits += [(m.start(), m.end(), "lookalike") for m in look.finditer(text) if m.group() != name]
        for start, end, kind in sorted(hits):
            if kind == "lookalike":
                alike[text[start:end]] = alike.get(text[start:end], 0) + 1
                if not a.lookalikes:
                    continue
            ln = text.count("\n", 0, start)
            col = start - (text.rfind("\n", 0, start) + 1)
            src = lines[ln] if ln < len(lines) else ""
            if kind is None:
                kind = {"s": "string", "m": "comment", "d": "doc"}.get(kinds[start], "code")
                if kind == "code":
                    before = src[:col]
                    recv = re.search(r"([\w$\])]+)\s*\.\s*$", before)
                    if recv:
                        kind = f"code:attr({recv.group(1)})"
                    elif DEF.search(before):
                        kind = "code:def"
                    elif IMPORT.match(src):
                        kind = "code:import"
            counts[kind.split("(")[0]] = counts.get(kind.split("(")[0], 0) + 1
            rows.append(f"{os.path.normpath(path)}:{ln + 1}:{col + 1}  {kind}  {src.strip()[:140]}")
    for r in rows[: a.max]:
        print(r)
    if len(rows) > a.max:
        print(f"... {len(rows) - a.max} more (raise --max or narrow the paths)")
    print("TOTAL " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())) if rows else "TOTAL none")
    if alike:
        print("LOOKALIKE " + " ".join(f"{k}={v}" for k, v in sorted(alike.items(), key=lambda x: -x[1])))
    return 1 if rows else 0


def apply(a):
    if len(a.args) != 2 or not a.sel:
        print("usage: codemod.py apply OLD NEW --from SELECTED [--write]", file=sys.stderr); return 2
    old, new = a.args
    loc = re.compile(r"^\s*(.+?):(\d+):(\d+)\b")
    by_file = {}
    for raw in open(a.sel, encoding="utf-8"):
        if not raw.strip() or raw.lstrip().startswith("#") or raw.startswith(("TOTAL", "...")):
            continue
        m = loc.match(raw)
        if not m:
            print(f"can't read location: {raw.strip()}", file=sys.stderr); return 2
        by_file.setdefault(m.group(1), set()).add((int(m.group(2)), int(m.group(3))))
    bad, out = [], {}
    for path, spots in sorted(by_file.items()):
        text = read_text(path)
        if text is None:
            bad.append(f"{path}: can't read"); continue
        lines = text.splitlines(keepends=True)
        for ln, col in sorted(spots, reverse=True):
            line = lines[ln - 1] if 0 < ln <= len(lines) else ""
            s = col - 1
            ok = line[s:s + len(old)] == old and not re.match(r"[\w$]", line[s + len(old):s + len(old) + 1]) \
                and not (s > 0 and re.match(r"[\w$]", line[s - 1]))
            if not ok:
                bad.append(f"{path}:{ln}:{col}: {old!r} not found there: {line.strip()[:100]}"); continue
            lines[ln - 1] = line[:s] + new + line[s + len(old):]
        out[path] = (text, "".join(lines))
    if bad:
        for b in bad:
            print("MISMATCH", b)
        print("nothing written"); return 1
    for path, (before, after) in out.items():
        if a.write:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(after)
        else:
            sys.stdout.writelines(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                                       f"a/{path}", f"b/{path}"))
    n = sum(len(s) for s in by_file.values())
    print(f"{'WROTE' if a.write else 'DRY RUN'} {n} locations in {len(out)} files")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["find", "apply"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--max", type=int, default=400)
    ap.add_argument("--from", dest="sel")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--lookalikes", action="store_true")
    try:
        a = ap.parse_args()
    except SystemExit as e:
        return 0 if e.code == 0 else 2
    if a.command == "find":
        if not a.args or not re.fullmatch(r"[\w$]+", a.args[0]):
            print("usage: codemod.py find NAME [PATH ...]  (NAME is one identifier)", file=sys.stderr); return 2
        return find(a)
    return apply(a)


if __name__ == "__main__":
    sys.exit(main())
