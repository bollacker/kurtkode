"""The old CRM export. Its fetch_user reads CRM ids and has nothing to do with app.users."""
CRM = {"c-1": {"name": "Ada L."}}


def fetch_user(crm_id):
    return CRM.get(crm_id)
