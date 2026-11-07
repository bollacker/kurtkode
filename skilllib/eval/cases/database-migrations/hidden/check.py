#!/usr/bin/env python3
"""Hidden check for database-migrations/order-currency. Run in the project folder. Exit 0 = pass.
Builds a populated database at migration 0002 (the production state), then runs the project's own
`migrate.py up`, `down`, `up` against it and checks:
1. Applied migrations were not edited (a new migration is needed; production already ran 0001 and 0002).
2. After up: orders.currency exists, every existing order is 'USD', an order inserted without a currency or with
   NULL is rejected, one with a currency is accepted; no rows lost in any table (the ON DELETE CASCADE trap of a
   table rebuild with foreign keys on); indexes and foreign keys still in place; integrity and FK checks clean.
3. After down: currency gone, same data, indexes and foreign keys in place. Up again works.
4. The project's tests pass."""
import hashlib, os, shutil, sqlite3, subprocess, sys, tempfile

case = os.environ["CASE_DIR"]
problems = []
for line in open(os.path.join(case, "hidden", "protected.sha256")):
    digest, path = line.split()
    if not os.path.exists(path) or hashlib.sha256(open(path, "rb").read()).hexdigest() != digest:
        problems.append(f"{path} was edited or removed; production already applied it, so changes there never run")

tmp = tempfile.mkdtemp()
db = os.path.join(tmp, "prod.db")


def build():
    c = sqlite3.connect(db, isolation_level=None)
    c.execute("PRAGMA foreign_keys = ON")
    c.execute("CREATE TABLE schema_migrations (version TEXT PRIMARY KEY)")
    for f, v in [("0001_customers_orders.sql", "0001"), ("0002_order_items.sql", "0002")]:
        text = open(os.path.join(case, "fixtures", "order-currency", "migrations", f)).read()
        c.executescript(text.partition("-- migrate:down")[0].replace("-- migrate:up", "", 1))
        c.execute("INSERT INTO schema_migrations VALUES (?)", (v,))
    c.executescript("BEGIN;" + open(os.path.join(case, "hidden", "seed.sql")).read() + "COMMIT;")
    c.close()


def migrate(cmd):
    p = subprocess.run([sys.executable, "migrate.py", "--db", db, cmd], capture_output=True, text=True)
    if p.returncode != 0:
        problems.append(f"migrate.py {cmd} failed: {(p.stdout + p.stderr)[-500:]}")
    return p.returncode == 0


def snapshot(c):
    return {
        "customers": c.execute("SELECT id, email, name FROM customers ORDER BY id").fetchall(),
        "orders": c.execute("SELECT id, customer_id, total_cents, created_at FROM orders ORDER BY id").fetchall(),
        "items": c.execute("SELECT id, order_id, sku, qty, price_cents FROM order_items ORDER BY id").fetchall(),
    }


def structure(c, when):
    idx = {r[1] for r in c.execute("PRAGMA index_list(orders)")}
    cols = {tuple(r[2] for r in c.execute(f"PRAGMA index_info('{i}')")) for i in idx}
    if ("customer_id",) not in cols:
        problems.append(f"{when}: the index on orders(customer_id) is gone")
    if "orders" not in {r[2] for r in c.execute("PRAGMA foreign_key_list(order_items)")}:
        problems.append(f"{when}: order_items no longer references orders")
    if "customers" not in {r[2] for r in c.execute("PRAGMA foreign_key_list(orders)")}:
        problems.append(f"{when}: orders no longer references customers")
    if c.execute("PRAGMA foreign_key_check").fetchall():
        problems.append(f"{when}: foreign key violations")
    if c.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        problems.append(f"{when}: integrity_check failed")


try:
    build()
    c = sqlite3.connect(db)
    before = snapshot(c)
    c.close()
    if migrate("up"):
        c = sqlite3.connect(db)
        c.execute("PRAGMA foreign_keys = ON")
        cols = [r[1] for r in c.execute("PRAGMA table_info(orders)")]
        if "currency" not in cols:
            problems.append(f"after up: orders has no currency column ({cols})")
        else:
            if snapshot(c) != before:
                problems.append("after up: data changed or rows lost (compare customers, orders, order_items)")
            cur = c.execute("SELECT currency, count(*) FROM orders GROUP BY currency").fetchall()
            if cur != [("USD", 5)]:
                problems.append(f"after up: existing orders' currencies are {cur}, want all 5 'USD'")
            for sql in ["INSERT INTO orders (customer_id, total_cents) VALUES (1, 100)",
                        "INSERT INTO orders (customer_id, total_cents, currency) VALUES (1, 100, NULL)",
                        "UPDATE orders SET currency = NULL WHERE id = 1"]:
                try:
                    with c:
                        c.execute(sql)
                    problems.append(f"after up: accepted `{sql}` (currency must be explicit and never NULL)")
                    with c:
                        c.execute("DELETE FROM orders WHERE id > 5")
                except sqlite3.DatabaseError:
                    pass
            try:
                with c:
                    c.execute("INSERT INTO orders (id, customer_id, total_cents, currency) VALUES (99, 2, 700, 'EUR')")
                    c.execute("DELETE FROM orders WHERE id = 99")
            except sqlite3.DatabaseError as e:
                problems.append(f"after up: a valid order with currency 'EUR' was rejected: {e}")
            structure(c, "after up")
        c.close()
        if migrate("down"):
            c = sqlite3.connect(db)
            if "currency" in [r[1] for r in c.execute("PRAGMA table_info(orders)")]:
                problems.append("after down: orders still has a currency column")
            if snapshot(c) != before:
                problems.append("after down: data changed or rows lost")
            structure(c, "after down")
            c.close()
            if migrate("up"):
                c = sqlite3.connect(db)
                if snapshot(c) != before:
                    problems.append("after up, down, up: data changed or rows lost")
                c.close()
except Exception as e:
    problems.append(f"check crashed: {e!r}")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

t = subprocess.run([sys.executable, "-m", "unittest"], capture_output=True, text=True)
if t.returncode != 0:
    problems.append("project tests fail:\n" + t.stderr[-600:])

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
