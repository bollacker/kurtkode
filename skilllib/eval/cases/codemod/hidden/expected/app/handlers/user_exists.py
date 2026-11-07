from app.users.api import load_user as get


def user_exists(user_id):
    try:
        get(user_id)
        return True
    except KeyError:
        return False
