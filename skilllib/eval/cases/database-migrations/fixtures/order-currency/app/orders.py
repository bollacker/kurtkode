"""Order queries used by the shop."""
import sqlite3


def connect(path="app.db"):
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def create_order(conn, customer_id, items):
    """items: list of (sku, qty, price_cents). Returns the new order id."""
    total = sum(qty * price for _, qty, price in items)
    with conn:
        cur = conn.execute("INSERT INTO orders (customer_id, total_cents) VALUES (?, ?)", (customer_id, total))
        conn.executemany("INSERT INTO order_items (order_id, sku, qty, price_cents) VALUES (?, ?, ?, ?)",
                         [(cur.lastrowid, sku, qty, price) for sku, qty, price in items])
    return cur.lastrowid


def customer_orders(conn, customer_id):
    return conn.execute("SELECT id, total_cents FROM orders WHERE customer_id = ? ORDER BY id",
                        (customer_id,)).fetchall()
