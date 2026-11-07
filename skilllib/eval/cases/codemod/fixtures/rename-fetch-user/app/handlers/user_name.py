from app.users import fetch_user


def user_name(user_id):
    return fetch_user(user_id)["name"]
