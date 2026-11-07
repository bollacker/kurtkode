from app.users.api import load_user


def show_user(user_id):
    return {"status": 200, "user": load_user(user_id)}
