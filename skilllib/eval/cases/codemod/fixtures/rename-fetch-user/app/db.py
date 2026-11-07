"""A tiny in-memory table store standing in for the database."""
TABLES = {"users": {1: {"id": 1, "name": "Ada", "bio": "math"}, 2: {"id": 2, "name": "Linus"}}}


def get(table, key):
    return TABLES[table].get(key)


def ids(table):
    return sorted(TABLES[table])
