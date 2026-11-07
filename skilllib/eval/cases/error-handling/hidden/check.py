#!/usr/bin/env python3
"""Hidden check for error-handling/silent-config. Run in the project folder. Exit 0 = pass.
Bad settings must raise config.ConfigError (message names the file, or APP_PORT) from config.load AND from
server.start, which also swallows errors and falls back to defaults. A missing file still gives the defaults, but
other read errors (the path is a directory) must not be silently treated as missing."""
import json, logging, os, subprocess, sys, tempfile

sys.path.insert(0, os.getcwd())
problems = []
p = subprocess.run([sys.executable, "-m", "unittest", "-q"], capture_output=True, text=True, timeout=120)
if p.returncode != 0:
    problems.append("the project's own tests fail:\n" + (p.stdout + p.stderr)[-600:])

try:
    from svc import config, server
except Exception as e:
    print(f"FAIL: can't import svc: {e!r}")
    sys.exit(1)

logging.disable(logging.CRITICAL)  # a swallowing server.start logs a warning per case
DEFAULTS = {"port": 8080, "workers": 4, "allowlist": [], "debug": False}


def write(text):
    path = os.path.join(tempfile.mkdtemp(), "settings.json")
    with open(path, "w") as f:
        f.write(text)
    return path


def expect_error(label, path, env=None, must_mention=None, via=("load", "start"), mention_path=True):
    for name in via:
        fn = config.load if name == "load" else server.start
        try:
            got = fn(path, env={} if env is None else env)
        except config.ConfigError as e:
            for word in ([path] if mention_path else []) + ([must_mention] if must_mention else []):
                if word not in str(e):
                    problems.append(f"{label}: {name}() raised ConfigError but the message doesn't mention {word!r}: {e}")
            continue
        except Exception as e:
            problems.append(f"{label}: {name}() raised {type(e).__name__} ({e}), want ConfigError")
            continue
        shown = got if isinstance(got, dict) else getattr(got, "__dict__", got)
        problems.append(f"{label}: {name}() returned {shown!r} instead of raising ConfigError")


base = {"port": 9000, "workers": 2, "allowlist": ["10.0.0.1"], "debug": False}
try:
    missing = os.path.join(tempfile.mkdtemp(), "settings.json")
    if config.load(missing, env={}) != DEFAULTS:
        problems.append("missing file: config.load no longer returns the defaults")
    if server.start(missing, env={}).port != 8080:
        problems.append("missing file: server.start no longer starts on the default port")
    if config.load(missing, env={"APP_PORT": "9001"})["port"] != 9001:
        problems.append("APP_PORT=9001 with no file: port is not 9001")
    good = config.load(write(json.dumps(base)), env={})
    if dict(good) != base:
        problems.append(f"valid file: got {good!r}, want {base!r}")

    expect_error("invalid JSON", write('{"port": 9000,, }'))
    expect_error("top level is a list", write("[1, 2]"))
    expect_error("unknown key", write(json.dumps({**base, "alowlist": ["10.0.0.2"]})), must_mention="alowlist")
    for key, bad in (("port", "9000"), ("port", 0), ("port", 70000), ("port", 80.5), ("workers", "four"),
                     ("workers", 0), ("allowlist", "10.0.0.1"), ("allowlist", [10]), ("debug", "yes")):
        expect_error(f"{key}={bad!r}", write(json.dumps({**base, key: bad})), must_mention=key)
    good_path = write(json.dumps(base))
    for bad in ("abc", "0", "99999"):
        expect_error(f"APP_PORT={bad!r}", good_path, env={"APP_PORT": bad}, must_mention="APP_PORT", mention_path=False)

    a_dir = tempfile.mkdtemp()
    for name, fn in (("load", config.load), ("start", server.start)):
        try:
            fn(a_dir, env={})
            problems.append(f"settings path is a directory: {name}() carried on with defaults instead of failing")
        except (config.ConfigError, OSError):
            pass
except Exception as e:
    problems.append(f"hidden checks crashed: {e!r}")

for x in dict.fromkeys(problems):
    print("FAIL:", x)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
