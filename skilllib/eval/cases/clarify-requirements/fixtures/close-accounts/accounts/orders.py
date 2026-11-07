"""Orders and the revenue numbers finance reports from."""


def add_order(conn, user_id, amount_cents, placed_on):
    cur = conn.execute(
        "INSERT INTO orders (user_id, amount_cents, placed_on) VALUES (?, ?, ?)",
        (user_id, amount_cents, placed_on),
    )
    conn.commit()
    return cur.lastrowid


def orders_for_user(conn, user_id):
    return conn.execute("SELECT * FROM orders WHERE user_id = ? ORDER BY placed_on", (user_id,)).fetchall()


def revenue(conn, month):
    """Total order amount in cents for a month given as 'YYYY-MM'."""
    row = conn.execute(
        "SELECT COALESCE(SUM(amount_cents), 0) FROM orders WHERE substr(placed_on, 1, 7) = ?", (month,)
    ).fetchone()
    return row[0]
