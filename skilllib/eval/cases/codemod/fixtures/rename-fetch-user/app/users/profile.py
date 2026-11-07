from app.metrics import count

from .api import fetch_user


def fetch_user_profile(user_id):
    count("fetch_user_profile")
    user = fetch_user(user_id)
    return {"name": user["name"], "bio": user.get("bio", "")}
