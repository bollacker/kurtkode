import json
import os
import tempfile
import unittest

from svc import config, server


def settings_file(data):
    path = os.path.join(tempfile.mkdtemp(), "settings.json")
    with open(path, "w") as f:
        json.dump(data, f)
    return path


class ConfigTest(unittest.TestCase):
    def test_missing_file_uses_defaults(self):
        missing = os.path.join(tempfile.mkdtemp(), "settings.json")
        self.assertEqual(config.load(missing, env={}), config.DEFAULTS)

    def test_values_from_file(self):
        path = settings_file({"port": 9090, "workers": 8, "allowlist": ["10.0.0.1"], "debug": True})
        cfg = config.load(path, env={})
        self.assertEqual((cfg["port"], cfg["workers"], cfg["allowlist"], cfg["debug"]), (9090, 8, ["10.0.0.1"], True))

    def test_env_overrides_port(self):
        self.assertEqual(config.load(settings_file({"port": 9090}), env={"APP_PORT": "7000"})["port"], 7000)

    def test_server_uses_settings(self):
        srv = server.start(settings_file({"allowlist": ["10.0.0.1"]}), env={})
        self.assertTrue(srv.allows("10.0.0.1"))
        self.assertFalse(srv.allows("10.0.0.2"))
