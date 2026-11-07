from app import log
from app.remote.client import RemoteClient
from app.users import api


def import_partner_users(client: RemoteClient, ids):
    """Copy partner names onto our users. Returns the ids that changed."""
    changed = []
    for uid in ids:
        theirs = client.fetch_user(uid)
        ours = api.load_user(uid)
        if theirs and theirs["name"] != ours["name"]:
            log.info("fetch_user mismatch for %s", uid)
            changed.append(uid)
    return changed
