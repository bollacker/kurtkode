#!/usr/bin/env python3
"""Apply or roll back the SQL migrations in migrations/.

Usage: migrate.py [--db PATH] up | down | status
  up      apply every pending migration, in file-name order
  down    roll back the most recently applied migration
  status  list migrations and whether each is applied

A migration is migrations/NNNN_name.sql with two sections, '-- migrate:up' and '-- migrate:down'. Applied
versions (the NNNN prefix) are recorded in the table schema_migrations. Each section is run as a script with no
implicit transaction, so it should wrap its statements in BEGIN; ... COMMIT; itself (statements that must run
outside a transaction, such as some PRAGMAs, go before BEGIN). The connection enforces foreign keys, as the app does.
"""
import argparse, os, sqlite3, sys

MIGRATIONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "migrations")


def sections(path):
    text = open(path).read()
    up, _, down = text.partition("-- migrate:down")
    return up.replace("-- migrate:up", "", 1), down


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default="app.db")
    ap.add_argument("command", choices=["up", "down", "status"])
    a = ap.parse_args()
    conn = sqlite3.connect(a.db, isolation_level=None)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)")
    applied = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
    files = sorted(f for f in os.listdir(MIGRATIONS) if f.endswith(".sql"))
    if a.command == "status":
        for f in files:
            print(("applied  " if f[:4] in applied else "pending  ") + f)
    elif a.command == "up":
        for f in files:
            if f[:4] not in applied:
                conn.executescript(sections(os.path.join(MIGRATIONS, f))[0])
                conn.execute("INSERT INTO schema_migrations (version) VALUES (?)", (f[:4],))
                print("applied", f)
    else:
        done = [f for f in files if f[:4] in applied]
        if not done:
            print("nothing to roll back")
            return 0
        f = done[-1]
        conn.executescript(sections(os.path.join(MIGRATIONS, f))[1])
        conn.execute("DELETE FROM schema_migrations WHERE version = ?", (f[:4],))
        print("rolled back", f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
