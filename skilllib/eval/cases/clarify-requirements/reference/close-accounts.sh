# Reference: soft delete (deleted_at), orders kept, deleted users hidden; assumptions recorded.
python3 - <<'PY'
import re
p = "accounts/schema.sql"
s = open(p).read()
s = s.replace("    created_at TEXT NOT NULL DEFAULT (datetime('now'))\n);",
              "    created_at TEXT NOT NULL DEFAULT (datetime('now')),\n    deleted_at TEXT\n);", 1)
open(p, "w").write(s)

p = "accounts/users.py"
s = open(p).read()
s = s.replace('"SELECT * FROM users WHERE email = ?"', '"SELECT * FROM users WHERE email = ? AND deleted_at IS NULL"')
s = s.replace('"SELECT * FROM users ORDER BY id"', '"SELECT * FROM users WHERE deleted_at IS NULL ORDER BY id"')
s += '''

def delete_user(conn, user_id):
    """Close an account: mark it deleted and hide it. Orders stay (revenue history must not change)."""
    cur = conn.execute(
        "UPDATE users SET deleted_at = datetime('now') WHERE id = ? AND deleted_at IS NULL", (user_id,)
    )
    conn.commit()
    return cur.rowcount == 1
'''
open(p, "w").write(s)

p = "cli.py"
s = open(p).read()
s = s.replace('    sub.add_parser("list-users")\n',
              '    sub.add_parser("list-users")\n    p = sub.add_parser("delete-user")\n    p.add_argument("user_id", type=int)\n')
s = s.replace('    elif a.cmd == "revenue":',
              '    elif a.cmd == "delete-user":\n        if not users.delete_user(conn, a.user_id):\n'
              '            print(f"no active user {a.user_id}", file=sys.stderr)\n            return 1\n'
              '    elif a.cmd == "revenue":')
open(p, "w").write(s)
PY
cat > ASSUMPTIONS.md <<'MD'
# Assumptions for delete-user

- "Delete" means close the account, not erase the row: orders.user_id cascades on delete
  (accounts/schema.sql:10), so a hard delete would remove the user's orders and change revenue,
  which finance uses for the monthly close (README). Chosen: soft delete (users.deleted_at), orders kept.
- Deleted users are hidden from list_users and find_user. Their email stays reserved (UNIQUE).
- Existing databases need `ALTER TABLE users ADD COLUMN deleted_at TEXT` (not automated).
- If personal data must be erased (e.g. a privacy request), anonymize email/name on top of this; not done.
MD
