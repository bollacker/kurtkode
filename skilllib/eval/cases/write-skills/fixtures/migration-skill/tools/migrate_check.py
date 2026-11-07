"""Check migrations: numbering, up/down pairs, and up -> down -> up on a scratch SQLite database. Exit 1 on failure."""
import pathlib
import re
import sqlite3
import sys

root = pathlib.Path(__file__).resolve().parent.parent / "migrations"
ups = sorted(root.glob("*.up.sql"))
problems = []
for i, up in enumerate(ups, 1):
    if not re.match(rf"^{i:04d}_[a-z0-9_]+\.up\.sql$", up.name):
        problems.append(f"{up.name}: expected number {i:04d}")
    if not up.with_name(up.name.replace(".up.sql", ".down.sql")).exists():
        problems.append(f"{up.name}: no matching .down.sql")


def schema(db):
    return sorted(r[0] for r in db.execute("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL"))


if not problems:
    db = sqlite3.connect(":memory:")
    try:
        for up in ups:
            db.executescript(up.read_text())
        first = schema(db)
        for up in reversed(ups):
            db.executescript(up.with_name(up.name.replace(".up.sql", ".down.sql")).read_text())
        if schema(db):
            problems.append("downs did not remove everything")
        for up in ups:
            db.executescript(up.read_text())
        if schema(db) != first:
            problems.append("schema differs after up -> down -> up")
    except sqlite3.Error as e:
        problems.append(f"sqlite error: {e}")
for p in problems:
    print("FAIL:", p)
print("migrations OK" if not problems else "migrations FAILED")
sys.exit(1 if problems else 0)
