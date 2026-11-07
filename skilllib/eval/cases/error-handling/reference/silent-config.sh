# Reference: validate every setting and raise ConfigError naming the file (or APP_PORT) and the key; only a missing
# file means defaults; server.start lets the error propagate instead of starting with defaults.
cat > svc/config.py <<'PY'
"""Service settings: settings.json in the working directory, and APP_PORT in the environment overrides the port."""
import json
import os

DEFAULTS = {"port": 8080, "workers": 4, "allowlist": [], "debug": False}


class ConfigError(Exception):
    """The settings can't be used."""


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


CHECKS = {
    "port": (lambda v: _is_int(v) and 1 <= v <= 65535, "an integer from 1 to 65535"),
    "workers": (lambda v: _is_int(v) and v >= 1, "an integer of at least 1"),
    "allowlist": (lambda v: isinstance(v, list) and all(isinstance(x, str) for x in v), "a list of strings"),
    "debug": (lambda v: isinstance(v, bool), "true or false"),
}


def load(path="settings.json", env=None):
    env = os.environ if env is None else env
    cfg = dict(DEFAULTS)
    try:
        with open(path) as f:
            text = f.read()
    except FileNotFoundError:
        text = None
    except OSError as e:
        raise ConfigError(f"{path}: can't read settings: {e}") from e
    if text is not None:
        try:
            data = json.loads(text)
        except json.JSONDecodeError as e:
            raise ConfigError(f"{path}: not valid JSON: {e}") from e
        if not isinstance(data, dict):
            raise ConfigError(f"{path}: settings must be a JSON object, got {type(data).__name__}")
        for key, value in data.items():
            if key not in CHECKS:
                raise ConfigError(f"{path}: unknown setting {key!r} (known: {', '.join(CHECKS)})")
            ok, want = CHECKS[key]
            if not ok(value):
                raise ConfigError(f"{path}: {key} must be {want}, got {value!r}")
            cfg[key] = value
    if env.get("APP_PORT"):
        raw = env["APP_PORT"]
        try:
            port = int(raw)
        except ValueError:
            port = None
        if port is None or not 1 <= port <= 65535:
            raise ConfigError(f"APP_PORT must be a port number from 1 to 65535, got {raw!r} (settings file {path})")
        cfg["port"] = port
    return cfg
PY
python3 - <<'PY'
p = "svc/server.py"
s = open(p).read()
s = s.replace('''    try:
        cfg = config.load(path, env)
    except Exception as e:
        log.warning("could not load settings (%s); starting with defaults", e)
        cfg = dict(config.DEFAULTS)
''', '''    cfg = config.load(path, env)  # bad settings stop start-up with ConfigError
''')
open(p, "w").write(s)
PY
