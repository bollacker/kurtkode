# svc

API service start-up. Settings come from `settings.json` (keys: port, workers, allowlist, debug); the environment
variable `APP_PORT` overrides the port. Python 3, standard library only. Tests: `python3 -m unittest`
