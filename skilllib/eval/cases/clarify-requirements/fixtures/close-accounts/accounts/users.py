"""User accounts."""


def create_user(conn, email, name):
    cur = conn.execute("INSERT INTO users (email, name) VALUES (?, ?)", (email.lower(), name))
    conn.commit()
    return cur.lastrowid


def find_user(conn, email):
    return conn.execute("SELECT * FROM users WHERE email = ?", (email.lower(),)).fetchone()


def list_users(conn):
    return conn.execute("SELECT * FROM users ORDER BY id").fetchall()
