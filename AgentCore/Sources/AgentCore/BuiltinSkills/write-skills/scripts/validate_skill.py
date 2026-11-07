#!/usr/bin/env python3
"""Validate agent skill folders (SKILL.md and its files) and, optionally, their test cases (cases.json).

Usage: validate_skill.py SKILL_DIR [SKILL_DIR ...] [--cases CASES_JSON ...]
                         [--max-desc 230] [--max-lines 150] [--max-bytes 6144]

Skill checks (errors): SKILL.md exists; front matter has exactly `name` and `description`; name is lowercase
letters, digits and single hyphens, at most 64 characters, equal to the folder name; description starts with
"Use when" and is at most --max-desc characters; the body is at most --max-lines lines and --max-bytes bytes;
every scripts/, references/ or assets/ path and relative link the body mentions exists.
Warnings (don't fail): very short body, no "# " title, nested references, scripts without an exit-code header,
stray files in the skill folder, tag-like text in the description.

Cases checks (errors): valid JSON; triggers.should has at least 5 and triggers.should_not at least 3 distinct
strings, none in both lists; each task has id, prompt and check, its fixture exists, and its prompt doesn't name
the skill (the folder containing cases.json is taken as the skill name). Warning: a task has no reference script.

Prints "OK <path>" or "FAIL <path>", then "  error: ..." / "  warn: ..." lines, then "RESULT ok=<n> failed=<n>".
Exit codes: 0 = no errors (warnings allowed), 1 = at least one error, 2 = usage error (bad arguments, missing path).
"""
import argparse, json, os, re, sys

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
PATH_RE = re.compile(r"(?:(?<=[\s`'\"(\[])|(?<=>/)|^)((?:scripts|references|assets)/[\w.\-/]+\.\w+)", re.M)
LINK_RE = re.compile(r"\]\(([^)\s#]+)\)")


def parse_front_matter(text):
    """Return (fields, duplicate keys, keys whose plain value is not valid YAML, body) or raise ValueError."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        raise ValueError("SKILL.md must start with a '---' front matter line")
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        raise ValueError("front matter is not closed with '---'")
    fields, dups, key = {}, [], None
    for raw in lines[1:end]:
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", raw)
        if m:
            key = m.group(1)
            if key in fields:
                dups.append(key)
            fields[key] = [m.group(2).strip()]
        elif key and (raw.startswith((" ", "\t")) or not raw.strip()):
            fields[key].append(raw.strip())
        elif raw.strip() and not raw.lstrip().startswith("#"):
            raise ValueError(f"cannot parse front matter line: {raw!r}")
    out, unsafe = {}, []
    for k, parts in fields.items():
        first, rest = parts[0], [p for p in parts[1:] if p]
        if first in (">", ">-", ">+", "|", "|-", "|+"):
            v = (" " if first.startswith(">") else "\n").join(rest)
        else:
            v = " ".join([first] + rest)
        quoted = len(v) >= 2 and v[0] == v[-1] and v[0] in "'\""
        if not quoted and first not in (">", ">-", ">+", "|", "|-", "|+") and re.search(r": | #|^[\[{&*!|>%@`]", v):
            unsafe.append(k)
        if quoted:
            v = v[1:-1].replace("\\\"", "\"") if v[0] == '"' else v[1:-1].replace("''", "'")
        out[k] = v.strip()
    return out, dups, unsafe, "\n".join(lines[end + 1:])


def check_skill(path, a):
    errors, warns = [], []
    d = os.path.abspath(path.rstrip("/"))
    if os.path.basename(d) == "SKILL.md":
        d = os.path.dirname(d)
    f = os.path.join(d, "SKILL.md")
    if not os.path.isfile(f):
        return [f"no SKILL.md in {d}"], warns
    text = open(f, encoding="utf-8", errors="replace").read()
    try:
        fm, dups, unsafe, body = parse_front_matter(text)
    except ValueError as e:
        return [str(e)], warns
    extra = sorted(set(fm) - {"name", "description"})
    if extra:
        errors.append(f"front matter may only have name and description; remove {', '.join(extra)}")
    for k in dups:
        errors.append(f"front matter key repeated: {k}")
    for k in unsafe:
        if k in ("name", "description"):
            errors.append(f"{k}: unquoted value contains ': ', ' #' or starts with a YAML symbol; reword or quote it")
    name, desc = fm.get("name", ""), fm.get("description", "")
    if not name:
        errors.append("name is missing")
    else:
        if not NAME_RE.match(name) or len(name) > 64:
            errors.append(f"name {name!r} must be lowercase letters, digits and single hyphens, at most 64 chars")
        if name != os.path.basename(d):
            errors.append(f"name {name!r} differs from the folder name {os.path.basename(d)!r}")
    if not desc:
        errors.append("description is missing")
    else:
        if len(desc) > a.max_desc:
            errors.append(f"description is {len(desc)} characters; the limit is {a.max_desc}")
        if not desc.startswith("Use when"):
            errors.append("description must start with 'Use when' (the trigger, not a summary)")
        if re.search(r"<[A-Za-z/][^>]*>", desc):
            warns.append("description contains tag-like text (<...>); some hosts reject it")
    body_lines = body.strip("\n").split("\n") if body.strip() else []
    nbytes = len(body.encode("utf-8"))
    if len(body_lines) > a.max_lines:
        errors.append(f"body is {len(body_lines)} lines; the limit is {a.max_lines} (move detail to references/)")
    if nbytes > a.max_bytes:
        errors.append(f"body is {nbytes} bytes; the limit is {a.max_bytes} (move detail to references/)")
    if len(body_lines) < 15:
        warns.append(f"body is only {len(body_lines)} lines: does it say what to do, and what done means?")
    if not any(l.startswith("# ") for l in body_lines):
        warns.append("body has no '# ' title")
    refs = set(PATH_RE.findall(body))
    refs |= {m for m in LINK_RE.findall(body) if not re.match(r"^[a-z]+:", m)}
    for r in sorted(refs):
        r = r.rstrip(".,:;")
        if not os.path.exists(os.path.join(d, r)):
            errors.append(f"body mentions {r}, which does not exist in the skill folder")
    for sub, dirs, files in os.walk(d):
        rel = os.path.relpath(sub, d)
        if rel == ".":
            stray = [x for x in files + dirs if x not in ("SKILL.md", "scripts", "references", "assets", "LICENSE",
                                                          "LICENSE.txt", ".DS_Store")]
            if stray:
                warns.append(f"files the agent will never read: {', '.join(sorted(stray))}")
        elif rel.startswith("references" + os.sep) and files:
            warns.append(f"{rel} is nested; keep references one level deep")
        elif rel == "scripts":
            for x in files:
                head = open(os.path.join(sub, x), errors="replace").read(3000).lower()
                if "exit" not in head:
                    warns.append(f"scripts/{x} has no exit-code description in its first lines")
    return errors, warns


def check_cases(path):
    errors, warns = [], []
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError) as e:
        return [f"cannot read cases: {e}"], warns
    cdir = os.path.dirname(os.path.abspath(path))
    skill = os.path.basename(cdir)
    t = data.get("triggers", {}) if isinstance(data, dict) else {}
    should, shouldnt = t.get("should", []), t.get("should_not", [])
    for label, lst, need in (("should", should, 5), ("should_not", shouldnt, 3)):
        if not isinstance(lst, list) or not all(isinstance(x, str) and x.strip() for x in lst):
            errors.append(f"triggers.{label} must be a list of non-empty strings")
            continue
        if len(set(lst)) < need:
            errors.append(f"triggers.{label} has {len(set(lst))} distinct requests; need at least {need}")
    if isinstance(should, list) and isinstance(shouldnt, list):
        both = set(map(str, should)) & set(map(str, shouldnt))
        if both:
            errors.append(f"in both should and should_not: {sorted(both)[:2]}")
    for i, task in enumerate(data.get("tasks", []) if isinstance(data, dict) else []):
        tid = task.get("id", f"#{i}")
        for k in ("id", "prompt", "check"):
            if not task.get(k):
                errors.append(f"task {tid}: missing {k}")
        fx = task.get("fixture")
        if fx and not os.path.isdir(os.path.join(cdir, fx)):
            errors.append(f"task {tid}: fixture {fx} not found")
        if skill and skill in task.get("prompt", ""):
            errors.append(f"task {tid}: the prompt names the skill ({skill}); write it as a user would")
        if not os.path.exists(os.path.join(cdir, "reference", f"{tid}.sh")):
            warns.append(f"task {tid}: no reference/{tid}.sh proving the check can pass")
    return errors, warns


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("skills", nargs="*", help="skill folders (or their SKILL.md)")
    ap.add_argument("--cases", action="append", default=[], help="a cases.json to check (repeatable)")
    ap.add_argument("--max-desc", type=int, default=230)
    ap.add_argument("--max-lines", type=int, default=150)
    ap.add_argument("--max-bytes", type=int, default=6144)
    a = ap.parse_args()
    items = [(p, "skill") for p in a.skills] + [(p, "cases") for p in a.cases]
    if not items:
        ap.print_usage(sys.stderr)
        return 2
    missing = [p for p, _ in items if not os.path.exists(p)]
    if missing:
        print(f"no such path: {', '.join(missing)}", file=sys.stderr)
        return 2
    ok = failed = 0
    for p, kind in items:
        errors, warns = check_skill(p, a) if kind == "skill" else check_cases(p)
        print(("FAIL " if errors else "OK ") + p)
        for e in errors:
            print("  error: " + e)
        for w in warns:
            print("  warn: " + w)
        ok, failed = (ok, failed + 1) if errors else (ok + 1, failed)
    print(f"RESULT ok={ok} failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
