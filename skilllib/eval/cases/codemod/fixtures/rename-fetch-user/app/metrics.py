"""Counters scraped by the dashboards. Metric names are matched by alert rules: never rename them."""
COUNTS = {}
KNOWN = ["fetch_user", "fetch_user_profile", "prefetch_users"]


def count(name):
    COUNTS[name] = COUNTS.get(name, 0) + 1
