from app.users.profile import fetch_user_profile


def profile_page(user_id):
    profile = fetch_user_profile(user_id)
    return f"<h1>{profile['name']}</h1><p>{profile['bio']}</p>"
