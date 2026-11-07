# Reference: one anchored pattern for the whole line, built from the README's format.
python3 - <<'PY'
p = "logparse.py"
s = open(p, encoding="utf-8").read()
old_start = s.index("REQUEST = re.compile(")
old_end = s.index("def main(")
new = '''REQUEST = re.compile(r"""
    ^(?:\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z | \\d{4}-\\d{2}-\\d{2}\\ \\d{2}:\\d{2}:\\d{2},\\d{3})
    \\ (?:DEBUG|INFO|WARN|ERROR)\\ +
    \\[api\\]\\ (?P<method>GET|POST|PUT|PATCH|DELETE)
    \\ (?P<path>\\S+)
    \\ user=(?:"(?P<quser>[^"]*)"|(?P<user>[^\\s"]+))
    \\ status=(?P<status>\\d{3})
    \\ took=(?P<num>\\d+(?:\\.\\d+)?)(?P<unit>ms|s)
    (?:\\ +[^\\s=]+=\\S+)*
    \\s*$
""", re.X)


def parse_line(line):
    m = REQUEST.match(line)
    if not m:
        return None
    user = m.group("quser") if m.group("quser") is not None else m.group("user")
    ms = float(m.group("num")) * (1000 if m.group("unit") == "s" else 1)
    return {"method": m.group("method"), "path": m.group("path"), "user": None if user == "-" else user,
            "status": int(m.group("status")), "ms": ms}


'''
open(p, "w", encoding="utf-8").write(s[:old_start] + new + s[old_end:])
PY
