from app.metrics import count

from .api import load_user


def fetch_user_profile(user_id):
    count("fetch_user_profile")
    user = load_user(user_id)
    return {"name": user["name"], "bio": user.get("bio", "")}
