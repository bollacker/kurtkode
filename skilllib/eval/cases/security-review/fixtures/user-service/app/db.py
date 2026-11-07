"""User store (sqlite3)."""
import sqlite3

SORT_COLUMNS = {"name": "name", "joined": "joined_at", "id": "id"}


def connect(path=":memory:"):
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT, email TEXT,"
                 " joined_at TEXT, is_admin INTEGER DEFAULT 0)")
    return conn


def add_user(conn, name, email, joined_at, is_admin=False):
    conn.execute("INSERT INTO users (name, email, joined_at, is_admin) VALUES (?, ?, ?, ?)",
                 (name, email, joined_at, int(is_admin)))


def list_users(conn, sort="name", limit=50):
    """Public user list (id, name), sorted by one of SORT_COLUMNS."""
    if sort not in SORT_COLUMNS:
        raise ValueError(f"unknown sort key: {sort}")
    sql = f"SELECT id, name FROM users WHERE is_admin = 0 ORDER BY {SORT_COLUMNS[sort]} LIMIT ?"
    return conn.execute(sql, (int(limit),)).fetchall()


def search_users(conn, term):
    """Public users (id, name) whose name contains term."""
    sql = f"SELECT id, name FROM users WHERE is_admin = 0 AND name LIKE '%{term}%'"
    return conn.execute(sql).fetchall()
