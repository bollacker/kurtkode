"""Load and validate client settings."""

DEFAULTS = {"max_attempts": 3, "backoff": 0.5}


def load(raw):
    """Merge raw settings over DEFAULTS and validate them.

    max_attempts: integer >= 0 (config files written before v2 use 0).
    backoff: seconds to wait between attempts, >= 0.
    """
    cfg = {**DEFAULTS, **raw}
    if not isinstance(cfg["max_attempts"], int) or cfg["max_attempts"] < 0:
        raise ValueError("max_attempts must be an integer >= 0")
    if cfg["backoff"] < 0:
        raise ValueError("backoff must be >= 0")
    return cfg
