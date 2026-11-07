from app.cache import prefetch_users
from app.users import list_users


def warm_cache():
    return prefetch_users([u["id"] for u in list_users()])
