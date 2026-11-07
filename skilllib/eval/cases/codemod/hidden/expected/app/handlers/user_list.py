from app.users.api import (
    load_user,
    list_users,
)


def user_list(selected=None):
    if selected:
        return [load_user(i) for i in selected]
    return list_users()
