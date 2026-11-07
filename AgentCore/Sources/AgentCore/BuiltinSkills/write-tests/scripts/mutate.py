#!/usr/bin/env python3
"""Small mutation tester: make one small change at a time to a source file (flip a comparison, swap and/or,
change a constant, drop a strip() or a raise), run your test command, and report the changes the tests did NOT
notice. Each surviving mutant is a bug your tests would miss.

Usage: mutate.py --file SRC [--lines A-B] [--max N] [--timeout SECS] -- TEST COMMAND [ARGS...]
       (a single quoted TEST COMMAND string is run by the shell)
  The test command must pass on the unmodified file. Mutants touch code only, never strings or comments.
  Works on any language; Python files are tokenized exactly and mutants that don't compile are skipped.
  A mutant that makes the tests hang (default limit: 5x the clean run, at least 5 s) counts as killed.

Prints one line per surviving mutant:  "SURVIVED file:line: <original line>  ->  <mutated line>"
then "RESULT killed=K survived=S total=N".

Exit codes: 0 = every mutant was killed, 1 = some survived, 2 = usage error or the tests fail before mutation.
The file is restored after every run and on Ctrl-C; a backup SRC.mutate-backup exists only while it runs.
"""
import argparse, io, os, re, signal, subprocess, sys, time, tokenize

OPS = {"<": "<=", "<=": "<", ">": ">=", ">=": ">", "==": "!=", "!=": "==", "&&": "||", "||": "&&",
       "+": "-", "-": "+", "+=": "-=", "-=": "+=", "and": "or", "or": "and", "True": "False", "False": "True",
       "true": "false", "false": "true"}
TOKEN = re.compile(r"<=|>=|==|!=|&&|\|\||\+=|-=|(?<![<>=!\-])[<>](?![<>=])|(?<![+\-*/=eE<>])[+\-](?![+\-=>])"
                   r"|\b(?:and|or|True|False|true|false)\b")
NUMBER = re.compile(r"(?<![\w.])\d+(?![\w.])")
CALL = re.compile(r"\.(?:strip|lstrip|rstrip|trim|trimStart|trimEnd|lower|upper|toLowerCase|toUpperCase)\(\)")
NOT = re.compile(r"\bnot\s+")
RAISE = re.compile(r"^(\s*)(raise|throw)\b.*$")
HASH_COMMENT = {".py", ".sh", ".rb", ".pl", ".yaml", ".yml", ".r", ".jl", ".ex", ".exs", ".nim", ".cr"}


def code_mask(src, ext):
    """Set of offsets that are code (not inside strings or comments)."""
    n = len(src)
    mask = bytearray(b"\x01") * n
    if ext == ".py":
        lines = src.splitlines(keepends=True)
        starts = [0]
        for ln in lines:
            starts.append(starts[-1] + len(ln))
        skip = {tokenize.STRING, tokenize.COMMENT}
        skip |= {getattr(tokenize, k) for k in ("FSTRING_START", "FSTRING_MIDDLE", "FSTRING_END") if hasattr(tokenize, k)}
        for t in tokenize.generate_tokens(io.StringIO(src).readline):
            if t.type in skip:
                a = starts[t.start[0] - 1] + t.start[1]
                b = starts[t.end[0] - 1] + t.end[1]
                mask[a:b] = b"\x00" * (b - a)
        return mask
    i, hash_c = 0, ext in HASH_COMMENT
    while i < n:
        c = src[i]
        if c in "\"'`":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            mask[i:j + 1] = b"\x00" * (min(j + 1, n) - i); i = j + 1
        elif src.startswith("//", i) or (hash_c and c == "#"):
            j = src.find("\n", i); j = n if j < 0 else j
            mask[i:j] = b"\x00" * (j - i); i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2); j = n if j < 0 else j + 2
            mask[i:j] = b"\x00" * (j - i); i = j
        else:
            i += 1
    return mask


def mutants(src, ext, lo, hi):
    mask = code_mask(src, ext)
    is_code = lambda a, b: all(mask[a:b])
    line_of = lambda off: src.count("\n", 0, off) + 1
    found = []
    def add(a, b, new):
        if is_code(a, b) and lo <= line_of(a) <= hi:
            found.append((a, b, new))
    for m in TOKEN.finditer(src):
        add(m.start(), m.end(), OPS[m.group()])
    for m in NUMBER.finditer(src):
        v = int(m.group()); add(m.start(), m.end(), str({0: 1, 1: 0}.get(v, v + 1)))
    for m in CALL.finditer(src):
        add(m.start(), m.end(), "")
    if ext == ".py":
        for m in NOT.finditer(src):
            add(m.start(), m.end(), "")
    off = 0
    for line in src.splitlines(keepends=True):
        m = RAISE.match(line.rstrip("\n"))
        if m:
            add(off + len(m.group(1)), off + len(line.rstrip("\n")), "pass" if ext == ".py" else ";")
        off += len(line)
    return sorted(set(found))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", required=True)
    ap.add_argument("--lines", default="", help="only mutate lines A-B (1-based, inclusive)")
    ap.add_argument("--max", type=int, default=300)
    ap.add_argument("--timeout", type=float, default=0, help="seconds per run (default: 5x the clean run, min 5)")
    ap.add_argument("command", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.command[1:] if a.command[:1] == ["--"] else a.command
    if not cmd or not os.path.isfile(a.file):
        ap.print_usage(sys.stderr); return 2
    lo, hi = 1, 10 ** 9
    if a.lines:
        try:
            lo, hi = (int(x) for x in a.lines.split("-"))
        except ValueError:
            print("--lines wants A-B", file=sys.stderr); return 2
    backup = a.file + ".mutate-backup"
    if os.path.exists(backup):
        print(f"{backup} exists: a previous run was interrupted. Restore it over {a.file} first.", file=sys.stderr)
        return 2
    src = open(a.file, encoding="utf-8").read()
    ext = os.path.splitext(a.file)[1].lower()
    env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
    stem = os.path.splitext(os.path.basename(a.file))[0]
    cache = os.path.join(os.path.dirname(a.file) or ".", "__pycache__")

    def run(limit):
        if os.path.isdir(cache):  # stale bytecode could hide a mutant
            for f in os.listdir(cache):
                if f.startswith(stem + "."):
                    os.remove(os.path.join(cache, f))
        shell = len(cmd) == 1
        try:
            return subprocess.run(cmd[0] if shell else cmd, shell=shell, capture_output=True, text=True,
                                  timeout=limit, env=env).returncode
        except subprocess.TimeoutExpired:
            return 124

    t0 = time.time()
    if run(a.timeout or 600) != 0:
        print("the test command fails on the unmodified file; fix that first", file=sys.stderr); return 2
    limit = a.timeout or max(5.0, 5 * (time.time() - t0))
    found = mutants(src, ext, lo, hi)[: a.max]
    open(backup, "w", encoding="utf-8").write(src)
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    killed = survived = 0
    try:
        for start, end, new in found:
            mutated = src[:start] + new + src[end:]
            if ext == ".py":
                try:
                    compile(mutated, a.file, "exec")
                except SyntaxError:
                    continue
            with open(a.file, "w", encoding="utf-8") as f:
                f.write(mutated)
            if run(limit) != 0:
                killed += 1
                continue
            survived += 1
            ln = src.count("\n", 0, start)
            old_line = src.splitlines()[ln].strip()
            new_line = mutated.splitlines()[ln].strip() if ln < len(mutated.splitlines()) else ""
            print(f"SURVIVED {a.file}:{ln + 1}: {old_line}  ->  {new_line}", flush=True)
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
    finally:
        with open(a.file, "w", encoding="utf-8") as f:
            f.write(src)
        os.remove(backup)
    print(f"RESULT killed={killed} survived={survived} total={killed + survived}")
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
