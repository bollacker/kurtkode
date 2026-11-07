from app import log
from app.users import api


def rename_user(user_id, name):
    user = api.load_user(user_id)
    log.info("fetch_user ok for %s", user_id)
    user["name"] = name
    return user
