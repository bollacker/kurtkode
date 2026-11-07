---
name: security-review
description: Use when asked for a security review or audit, or whether code is exploitable (injection, path traversal, auth bypass, SSRF, leaked keys). Attack path per finding, few false alarms. Not for ordinary bug review (code-review).
---

# Security review

Find the vulnerabilities an attacker could actually use, show the attack path for each, and report nothing you
can't back up.

## Fast path

For one function or a small diff: find where untrusted input enters, follow it to the sinks in it (step 3), and
apply steps 4–5 to anything you find. For "are there leaked secrets?": run step 2 only.

## Steps

1. **Scope and attack surface.** Reviewing a change: `git diff main...HEAD`; a repo: list the entry points (HTTP
   routes, CLI arguments, uploaded files, messages from queues, webhooks). Note who can reach each entry point
   (anyone on the internet, logged-in users, admins, the operator) and what is worth taking (other users' data,
   files on the server, credentials, money, code execution).

2. **Secrets.** Run `python3 <skill folder>/scripts/secret_scan.py` (working tree) and
   `python3 <skill folder>/scripts/secret_scan.py --history` (every commit). It prints location, kind, length
   and a fingerprint, never the value; exit 1 means something was found. Open each hit and judge it: a placeholder,
   test value or public checksum is not a finding. A secret that was ever committed is leaked even if a later commit
   removed it.

3. **Follow untrusted input to sinks.** For each entry point, trace the value through the code (`git grep -n`) to
   where it is used. Dangerous sinks and what makes them safe are in `references/sinks.md`; read it when the code
   uses a sink you are unsure about. The usual ones: SQL built by string formatting, shell commands, file paths,
   HTML output, deserialization (pickle, yaml.load), outgoing requests to a user-given URL, redirects, and object
   lookups by id without an owner check.

4. **Write the attack for each candidate.** Who (which attacker from step 1) sends what input, to which entry
   point, through which lines (entry → file:line → sink), and what they get. Read every step of that path; a
   check anywhere on it (allowlist, type conversion, escaping, containment check) can kill it. Where cheap and
   local, prove it: a unit-level call with the malicious input (`read_report("/etc/passwd")`), never against a
   live system or the network.

5. **Filter.** Report a finding only if the attack path is complete and you are confident it works. Drop:
   - input that comes only from trusted places: constants, the operator's config files, environment variables;
   - identifiers chosen from a fixed allowlist or converted to a number before use;
   - denial of service, rate limits, regex backtracking, missing security headers or TLS in a dev server, unless
     the user asked for them;
   - code in tests, examples and fixtures; outdated dependencies with no reachable known vulnerability;
   - theoretical issues (timing attacks on non-secrets, "might be unsafe if used elsewhere").

6. **Rate and fix.** Severity: **high** (remote, no or low privilege: data theft, file read/write, code
   execution, auth bypass), **medium** (needs a logged-in user or unusual setup), **low** (defense in depth worth
   doing). For each, the smallest fix: parameter binding, an allowlist, a resolved-path containment check, list
   arguments without a shell, an owner check.

## Rules

- **Never** print, paste or commit a secret's value: not in the report, logs, commands or commit messages. Cite
  file, line, commit and kind; the fingerprint from the scanner is enough to match duplicates.
- **Don't** rewrite git history, rotate keys or delete files on your own. Recommend: revoke and rotate the secret
  first (anyone with a clone has it), then purge history if the owner wants it.
- Don't report a pattern ("SQL built with an f-string", "path from user input") without the path that shows bad
  input reaches it: these look-alikes are the main source of false alarms.
- Don't attack anything outside the local copy; no network scans, no real credentials.

## When no one can answer

Assume the worst plausible exposure for each entry point (internet-facing unless the code or docs show otherwise),
state that assumption in the report, and finish. Ask before anything destructive (history rewrite, deleting
secrets from the tree, rotating keys); don't do it.

## Done means

A report in the file the user named (default SECURITY.md):

```
Scope: what was reviewed (range or paths). Exposure assumed: ...
Ran: secret_scan.py (tree, history) results; any local proof commands.

## Findings
- path:line — high|medium|low, category: what is wrong. Attack: who sends what, via which entry point, gets what.
  Fix: one sentence.

## Checked, not vulnerable
- look-alikes you examined and why they are safe (allowlist, int conversion, placeholder value)

## Not covered
- what you did not review
```

One bullet per finding, most severe first. A finding's bullet starts with `path:line` (for history: path and
commit); nothing else does.
