import app.users.api as users_api
from app import log


def nightly_check(ids):
    fetch_user_failures = 0
    for uid in ids:
        try:
            users_api.fetch_user(uid)
        except KeyError:
            fetch_user_failures += 1
            log.info("fetch_user failed for %s", uid)
    return fetch_user_failures
