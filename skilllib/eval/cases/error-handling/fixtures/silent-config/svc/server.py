"""Start-up of the API service."""
import logging

from . import config

log = logging.getLogger(__name__)


class Server:
    def __init__(self, cfg):
        self.port = cfg["port"]
        self.workers = cfg["workers"]
        self.allowlist = set(cfg["allowlist"])
        self.debug = cfg["debug"]

    def allows(self, client_ip):
        return client_ip in self.allowlist


def start(path="settings.json", env=None):
    try:
        cfg = config.load(path, env)
    except Exception as e:
        log.warning("could not load settings (%s); starting with defaults", e)
        cfg = dict(config.DEFAULTS)
    log.info("listening on port %s with %s workers", cfg["port"], cfg["workers"])
    return Server(cfg)
