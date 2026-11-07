"""Audit trail of stock movements. Kept in memory here; the service ships it to the audit log."""
import datetime

_entries = []


def record(event, **fields):
    _entries.append({"at": datetime.datetime.now().isoformat(), "event": event, **fields})


def entries():
    return list(_entries)


def clear():
    _entries.clear()
