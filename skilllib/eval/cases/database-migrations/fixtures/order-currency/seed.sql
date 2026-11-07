-- Anonymized sample of production data (what app.db holds).
INSERT INTO customers (id, email, name) VALUES
  (1, 'ana@example.com', 'Ana'), (2, 'bo@example.com', 'Bo'), (3, 'cy@example.com', 'Cy');
INSERT INTO orders (id, customer_id, total_cents, created_at) VALUES
  (1, 1, 2500, '2026-01-04 10:00:00'), (2, 1, 990, '2026-02-11 09:30:00'),
  (3, 2, 12000, '2026-03-01 17:45:00'), (4, 3, 450, '2026-03-02 08:00:00'),
  (5, 2, 3100, '2026-04-20 12:15:00');
INSERT INTO order_items (order_id, sku, qty, price_cents) VALUES
  (1, 'MUG', 1, 1500), (1, 'TEA', 2, 500), (2, 'TEA', 1, 990), (3, 'KETTLE', 1, 9000),
  (3, 'MUG', 2, 1500), (4, 'SPOON', 1, 450), (5, 'TEA', 4, 500), (5, 'MUG', 1, 1100);
