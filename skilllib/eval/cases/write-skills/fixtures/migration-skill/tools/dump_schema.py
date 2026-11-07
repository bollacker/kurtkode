"""Print the schema after applying every migration (redirect into schema.sql)."""
import pathlib
import sqlite3

root = pathlib.Path(__file__).resolve().parent.parent / "migrations"
db = sqlite3.connect(":memory:")
for up in sorted(root.glob("*.up.sql")):
    db.executescript(up.read_text())
for (sql,) in db.execute("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name"):
    print(sql + ";")
