---
name: error-handling
description: Use when errors are swallowed, silently defaulted or vague, or when adding input/config validation or choosing raise vs return vs retry. Makes failures specific and visible. Not for finding a crash's cause (systematic-debugging).
---

# Make failures visible and specific

No swallowed errors or silent fallbacks: each failure is either handled on purpose or reported with what failed,
where, and why.

## Fast path

One swallowed error in one place with an obvious contract: narrow the catch or raise a specific error with context,
and add a test that asserts it. Still do step 1's walk up the call path; another layer often swallows it again.

## Steps

1. **Inventory every handler on the path.** Search, then read each hit:
   `grep -rnE "except\b|catch\b|rescue\b|recover\(\)|_ = err|unwrap_or|try\?|\?\? |\|\| true" <src>`
   Also look for: `return None`/`null`/`-1`/empty on failure, `.get(key, default)` for required values, "log and
   continue", retries without a limit. Then follow the call path from where the error happens to the user: every
   caller, wrapper, framework handler and start-up routine may catch it again.

2. **Decide per failure** (record the decision for each handler):
   - **Absent but optional** (no config file, cache miss): handle here, catching only that case.
   - **Invalid input from outside** (user, request, file, config, environment): validate at the boundary and
     reject with a specific error. Defaults are for absent input, never for invalid input.
   - **Transient** (timeout, 503, lock busy): retry with a bound and backoff, then raise the last error.
   - **Optional side feature** (metrics, cache write): may degrade, but log a warning with the error.
   - **Anything else** (bugs, broken invariants, unexpected errors): don't catch; let it propagate to the
     top-level handler.

3. **Write good errors.** One specific type per kind of failure a caller may handle (`ConfigError`, `NotFound`), or
   the project's existing types. The message says what failed, where (file, key, line, id), the bad value and what
   was expected. Keep the cause: Python `raise ConfigError(...) from e`, JS `new Error(msg, { cause: e })`, Go
   `fmt.Errorf("load %s: %w", path, err)`, Rust `.with_context(...)` / `map_err`, Java `new X(msg, e)`.
   Log once, where the error is finally handled, not at every layer.

4. **Narrow every catch.** Specific types around the smallest block that can fail: `FileNotFoundError`, not
   `OSError` or `Exception` (a directory or a permission error is not "missing"); JS `if (e.code !== 'ENOENT')
   throw e`; Go `errors.Is(err, fs.ErrNotExist)`. Per-language idioms: `references/idioms.md`.

5. **Clean up on every path.** `with`/`finally`/`defer`/`using`/RAII for files, locks, connections and temp files;
   write to a temp file and rename so a failure leaves no half-written output.

6. **Test the failure paths.** One test per error case asserting the type and the key part of the message
   (`assertRaises`, `expect(...).toThrow(...)`, `errors.Is`), through the public entry point as well as the unit
   (start-up, request handler, CLI exit code). Test the fallbacks you kept, then run the full suite.

## Rules

- **Don't** catch an exception to make a crash or a failing test go away. Find why it is raised first.
- **Don't** use bare `except:`, `except Exception`, `catch (e) {}` or `_ = err` except at the top-level boundary
  (main, request handler, worker loop), and there log it with its trace and fail that request or the process.
- **Don't** return `None`/`null`/empty/a default for a failure when the caller can't tell it from success.
- **Don't** retry forever or swallow the last error after the retries.
- **Don't** change error types or messages other code depends on without grepping for the callers and tests.

## When no one can answer

When it's unclear whether a failure should be fatal: fail loudly for invalid data, config and input; degrade only for
optional side features; keep documented fallbacks. Record each choice in the report and continue.

## Done means

A report listing each handler changed (file:line, behavior before → after), the error types and example messages,
fallbacks kept on purpose and why, and the evidence: failure-path tests by name and the full-suite result.
