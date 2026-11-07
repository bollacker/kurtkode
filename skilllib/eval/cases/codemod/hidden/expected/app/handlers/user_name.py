from app.users import load_user


def user_name(user_id):
    return load_user(user_id)["name"]
