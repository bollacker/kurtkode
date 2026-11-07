class RemoteClient:
    """Client for the partner directory. Its fetch_user is the partner's API, not ours."""

    def __init__(self, records):
        self.records = records

    def fetch_user(self, user_id):
        return self.records.get(user_id)
