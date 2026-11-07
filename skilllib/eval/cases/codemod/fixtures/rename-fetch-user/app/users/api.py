"""User lookups backed by the main database."""
from app import db
from app.metrics import count

__all__ = ["fetch_user", "list_users"]


def fetch_user(user_id):
    count("fetch_user")
    row = db.get("users", user_id)
    if row is None:
        raise KeyError(f"fetch_user: no user {user_id}")
    return row


def list_users():
    return [fetch_user(i) for i in db.ids("users")]
