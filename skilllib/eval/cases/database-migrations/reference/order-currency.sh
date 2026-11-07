# Reference: a new migration that rebuilds orders (SQLite cannot add a NOT NULL column without a default),
# with foreign keys off around the rebuild so DROP TABLE doesn't cascade-delete order_items, indexes recreated,
# and a down that rebuilds the old shape. The app passes the currency explicitly.
cat > migrations/0003_order_currency.sql <<'SQL'
-- migrate:up
PRAGMA foreign_keys = OFF;
BEGIN;
CREATE TABLE orders_new (
  id INTEGER PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  currency TEXT NOT NULL CHECK (length(currency) = 3)
);
INSERT INTO orders_new (id, customer_id, total_cents, created_at, currency)
  SELECT id, customer_id, total_cents, created_at, 'USD' FROM orders;
DROP TABLE orders;
ALTER TABLE orders_new RENAME TO orders;
CREATE INDEX idx_orders_customer ON orders(customer_id);
PRAGMA foreign_key_check;
COMMIT;
PRAGMA foreign_keys = ON;

-- migrate:down
PRAGMA foreign_keys = OFF;
BEGIN;
CREATE TABLE orders_old (
  id INTEGER PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT INTO orders_old (id, customer_id, total_cents, created_at)
  SELECT id, customer_id, total_cents, created_at FROM orders;
DROP TABLE orders;
ALTER TABLE orders_old RENAME TO orders;
CREATE INDEX idx_orders_customer ON orders(customer_id);
COMMIT;
PRAGMA foreign_keys = ON;
SQL
python3 - <<'PY'
p = "app/orders.py"
s = open(p).read()
s = s.replace("def create_order(conn, customer_id, items):", "def create_order(conn, customer_id, items, currency):")
s = s.replace('"INSERT INTO orders (customer_id, total_cents) VALUES (?, ?)", (customer_id, total)',
              '"INSERT INTO orders (customer_id, total_cents, currency) VALUES (?, ?, ?)",\n'
              '                           (customer_id, total, currency)')
open(p, "w").write(s)
p = "tests/test_orders.py"
s = open(p).read()
s = s.replace('("TEA", 1, 500)])', '("TEA", 1, 500)], "USD")').replace('[("MUG", 1, 1500)])', '[("MUG", 1, 1500)], "USD")')
open(p, "w").write(s)
PY
python3 -m unittest -q
