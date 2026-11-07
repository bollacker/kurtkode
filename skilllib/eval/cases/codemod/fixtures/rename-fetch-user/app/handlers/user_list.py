from app.users.api import (
    fetch_user,
    list_users,
)


def user_list(selected=None):
    if selected:
        return [fetch_user(i) for i in selected]
    return list_users()
