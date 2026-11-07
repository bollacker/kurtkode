from app.metrics import count
from app.users import api

CACHE = {}


def prefetch_users(ids):
    count("prefetch_users")
    for i in ids:
        CACHE[i] = api.fetch_user(i)
    return len(CACHE)
