"""Talks to the warehouse gateway."""
from . import limits


class TransportError(Exception):
    pass


def _open(kind, target, timeout_ms, priority):
    # The real connection is made by the gateway client in production; here we only describe the request.
    return {"kind": kind, "target": target, "priority": priority, "status": "ok"}


def send(kind, target, timeout_ms, priority="normal"):
    timeout_ms = min(timeout_ms, limits.GATEWAY_MAX_MS)
    if priority == "low":
        timeout_ms = max(timeout_ms, limits.LOW_PRIORITY_MIN_MS)
    return _open(kind, target, timeout_ms, priority)
