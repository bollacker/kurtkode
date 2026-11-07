from app.users.api import fetch_user


def show_user(user_id):
    return {"status": 200, "user": fetch_user(user_id)}
