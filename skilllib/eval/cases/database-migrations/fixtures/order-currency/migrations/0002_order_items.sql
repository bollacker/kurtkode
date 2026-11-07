-- migrate:up
BEGIN;
CREATE TABLE order_items (
  id INTEGER PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  sku TEXT NOT NULL,
  qty INTEGER NOT NULL CHECK (qty > 0),
  price_cents INTEGER NOT NULL
);
CREATE INDEX idx_items_order ON order_items(order_id);
COMMIT;

-- migrate:down
BEGIN;
DROP TABLE order_items;
COMMIT;
