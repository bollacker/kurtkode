# Reference report: the two real vulnerabilities, each with an attack; the look-alikes dismissed.
cat > SECURITY.md <<'MD'
Scope: app/ (whole service). Exposure assumed: internet-facing, no authentication.
Ran: secret_scan.py (tree and history: no hits); local proofs with python3 -c calls shown below.

## Findings
- app/db.py:29 — high, SQL injection: `term` is formatted into the LIKE clause. Attack: anyone requests
  `/search?q=zz' UNION SELECT id, email FROM users --` and gets every user's email, admins included
  (reproduced locally with db.search_users). Fix: `name LIKE ?` with `('%' + term + '%',)` as a parameter.
- app/files.py:13 — high, path traversal: the check only rejects "..", but os.path.join drops REPORT_DIR for an
  absolute name. Attack: `GET /reports/%2Fetc%2Fpasswd` returns /etc/passwd (read_report('/etc/hosts') reproduced).
  Fix: resolve with os.path.realpath and require os.path.commonpath([REPORT_DIR, path]) == REPORT_DIR.

## Checked, not vulnerable
- db.list_users builds ORDER BY with an f-string, but the column comes from the SORT_COLUMNS allowlist and LIMIT is
  a bound parameter.
- files.avatar_path converts the id with int(), so no path characters get through.

## Not covered
- Authentication and rate limiting (none exist; out of scope for this review).
MD
