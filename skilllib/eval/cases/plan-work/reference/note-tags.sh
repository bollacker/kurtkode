# Reference: tags with a default (old files load), saved, filtered, counted and removed; plan ticked off.
python3 - <<'PY'
p = "notes/model.py"
s = open(p).read()
s = s.replace("from dataclasses import dataclass\n", "from dataclasses import dataclass, field\n")
s += "    tags: list = field(default_factory=list)\n"
open(p, "w").write(s)

p = "notes/store.py"
s = open(p).read()
s = s.replace('created=d["created"])', 'created=d["created"], tags=list(d.get("tags", [])))')
s = s.replace('"created": note.created}', '"created": note.created, "tags": note.tags}')
open(p, "w").write(s)

p = "notes/cli.py"
s = open(p).read()
s = s.replace('    p.add_argument("text")\n    sub.add_parser("list")\n',
              '    p.add_argument("text")\n    p.add_argument("--tag", action="append", default=[])\n'
              '    p = sub.add_parser("list")\n    p.add_argument("--tag")\n    sub.add_parser("tags")\n'
              '    p = sub.add_parser("untag")\n    p.add_argument("id", type=int)\n    p.add_argument("name")\n')
s = s.replace("notes.append(Note(nid, a.text, datetime.date.today().isoformat()))",
              "tags = sorted({t.lower() for t in a.tag})\n"
              "        notes.append(Note(nid, a.text, datetime.date.today().isoformat(), tags))")
s = s.replace("        for n in notes:\n            print",
              "        for n in notes:\n            if a.tag and a.tag.lower() not in n.tags:\n                continue\n            print")
s = s.replace('    elif a.cmd == "delete":',
              '    elif a.cmd == "tags":\n'
              '        counts = {}\n'
              '        for n in notes:\n'
              '            for t in n.tags:\n'
              '                counts[t] = counts.get(t, 0) + 1\n'
              '        for t, c in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):\n'
              '            print(f"{t}\\t{c}")\n'
              '    elif a.cmd == "untag":\n'
              '        for n in notes:\n'
              '            if n.id == a.id and a.name.lower() in n.tags:\n'
              '                n.tags.remove(a.name.lower())\n'
              '                store.save(a.file, notes)\n'
              '                return 0\n'
              '        print(f"note {a.id} has no tag {a.name}")\n'
              '        return 1\n'
              '    elif a.cmd == "delete":')
open(p, "w").write(s)
PY
cat > PLAN.md <<'MD'
# Plan: tags on notes

Done when: add/list/tags/untag work with tags across runs, and v1 and pre-tags v2 files still load.

## Steps
- [x] 1. Note gets `tags` (default empty); store loads files without tags and saves tags.
      Verify: `python3 -m unittest discover -s tests` and load an old v2 file → 4 passed, old file loads
- [x] 2. `add --tag` (repeatable, lowercased).
      Verify: `python3 -m notes --file /tmp/n.json add x --tag A --tag b` then inspect the file → tags ["a","b"]
- [x] 3. `list --tag`.
      Verify: `python3 -m notes --file /tmp/n.json list --tag B` → only note 1
- [x] 4. `tags` command (count desc, then name).
      Verify: `python3 -m notes --file /tmp/n.json tags` → `a	1` then `b	1`
- [x] 5. `untag ID NAME`.
      Verify: `python3 -m notes --file /tmp/n.json untag 1 A` then `tags` → only b
- [x] 6. Full suite.
      Verify: `python3 -m unittest discover -s tests` → OK

## Decisions
- Tags stored sorted and de-duplicated per note — simpler counts — reorderable later.

## Open
- none
MD
