"""Report and avatar files."""
import os

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
REPORT_DIR = os.path.join(DATA_DIR, "reports")
AVATAR_DIR = os.path.join(DATA_DIR, "avatars")


def read_report(name):
    """Contents of a report file under REPORT_DIR."""
    if ".." in name:
        raise ValueError("invalid report name")
    with open(os.path.join(REPORT_DIR, name), "rb") as f:
        return f.read()


def avatar_path(user_id):
    """Path of a user's avatar image."""
    return os.path.join(AVATAR_DIR, "%d.png" % int(user_id))
