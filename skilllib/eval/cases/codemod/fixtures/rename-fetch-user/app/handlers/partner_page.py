from app.remote.client import RemoteClient

CLIENT = RemoteClient({7: {"name": "Grace"}})


def partner_page(user_id):
    user = CLIENT.fetch_user(user_id)
    return {"status": 404} if user is None else {"status": 200, "user": user}
