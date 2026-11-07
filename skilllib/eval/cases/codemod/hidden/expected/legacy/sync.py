from app.users.api import load_user as fetch_app_user
from legacy.crm import fetch_user

LINKS = {"c-1": 1}


def stale_names():
    """CRM ids whose name differs from ours."""
    return [cid for cid, uid in LINKS.items() if fetch_user(cid)["name"] != fetch_app_user(uid)["name"]]
