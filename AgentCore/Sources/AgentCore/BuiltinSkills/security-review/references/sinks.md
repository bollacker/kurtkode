# Sinks and what makes them safe

Read this when tracing input (step 3) reaches a call you are unsure about. "Safe if" means the attack path dies there.

| Class | Dangerous sinks (examples) | Safe if |
|---|---|---|
| SQL injection | Python `cursor.execute(f"...{x}")`, `"..." % x`, `.format`; JS `` db.query(`...${x}`) ``; Go `db.Query("..." + x)`; Java `Statement.execute(s + x)`; ORM `raw()`, `text()`, `whereRaw` | values passed as bound parameters (`?`, `%s`, `$1`, `:name`); identifiers (column, table, ORDER BY) taken from a fixed allowlist or mapping, never the raw input |
| Command injection | `os.system`, `subprocess.*(..., shell=True)`, `os.popen`; Node `child_process.exec`; Go `exec.Command("sh", "-c", s)`; Ruby backticks, `system(str)` | argument list without a shell (`subprocess.run([...])`, `execFile`, `exec.Command(prog, args...)`), and the input can't start with `-` where it would be read as an option (use `--`) |
| Path traversal | `open(os.path.join(base, x))`, `send_file`, `fs.readFile(path.join(base, x))`, `filepath.Join`, archive extraction (zip slip) | the resolved path is checked to be inside base: `os.path.realpath` + `os.path.commonpath([base, p]) == base`; Node `path.resolve` + `startsWith(base + path.sep)`; Go `filepath.Rel` without `..`; or the name is reduced to a basename or converted to a number. A `".." in x` check alone is not enough: absolute paths (`/etc/passwd`) pass it because `join` drops `base` |
| XSS | HTML built by string concatenation, `innerHTML`, `dangerouslySetInnerHTML`, `v-html`, Jinja `|safe`, `Markup()`, `mark_safe` | template auto-escaping on and not bypassed; URLs checked for `javascript:` |
| Unsafe deserialization | `pickle.loads`, `yaml.load` without SafeLoader, `marshal`, Java `ObjectInputStream`, PHP `unserialize`, Node `node-serialize` | data only from a trusted source, or a data-only format (`json`, `yaml.safe_load`) |
| SSRF | server fetches a URL or host from input: `requests.get(x)`, `urllib.request.urlopen`, `fetch(x)`, webhooks, image proxies | an allowlist of hosts checked after resolving, with redirects off or re-checked; internal ranges (127.0.0.0/8, 10/8, 169.254.169.254, ::1) blocked |
| Open redirect | `redirect(request.args["next"])` | relative paths only, or a host allowlist |
| Broken access control | lookup by id from the request (`/orders/<id>`) without checking the owner; admin routes without a role check; trusting a client-sent `user_id` or `is_admin` | every object fetch filtered by the authenticated user; role checked on the server for each request |
| Auth and sessions | passwords stored with fast hashes (md5, sha1, sha256) or plain; tokens from `random`/`Math.random`; JWT with `alg: none` or unchecked signature; `==` comparison of secrets | bcrypt/scrypt/argon2; `secrets`/`crypto.randomBytes`; signature verified with a fixed algorithm; `hmac.compare_digest` |
| XML | `xml.etree`/`lxml` with external entities on, Java parsers default config (XXE) | `defusedxml`; external entities and DTDs disabled |
| Secrets | keys, tokens, passwords in source, config, history, logs, error messages | read from the environment or a secret store; placeholders in examples; logs scrubbed |
| Template injection | rendering a template whose source comes from input (`Template(x).render`, `render_template_string(x)`) | input only as template variables, never as template source |
