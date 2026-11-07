-- migrate:up
BEGIN;
CREATE TABLE customers (
  id INTEGER PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL
);
CREATE TABLE orders (
  id INTEGER PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_orders_customer ON orders(customer_id);
COMMIT;

-- migrate:down
BEGIN;
DROP INDEX idx_orders_customer;
DROP TABLE orders;
DROP TABLE customers;
COMMIT;
