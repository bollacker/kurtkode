"""Service settings: settings.json in the working directory, and APP_PORT in the environment overrides the port."""
import json
import os

DEFAULTS = {"port": 8080, "workers": 4, "allowlist": [], "debug": False}


class ConfigError(Exception):
    """The settings can't be used."""


def load(path="settings.json", env=None):
    env = os.environ if env is None else env
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
    cfg = dict(DEFAULTS)
    for key, value in data.items():
        if key in cfg:
            cfg[key] = value
    if env.get("APP_PORT"):
        try:
            cfg["port"] = int(env["APP_PORT"])
        except ValueError:
            pass
    try:
        cfg["workers"] = int(cfg["workers"])
    except (TypeError, ValueError):
        cfg["workers"] = DEFAULTS["workers"]
    if not isinstance(cfg["allowlist"], list):
        cfg["allowlist"] = []
    return cfg
