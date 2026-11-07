# Error-handling idioms by language

Read the section for the project's language when narrowing catches (step 4) or writing errors (step 3).

## Python

- Narrow: `except FileNotFoundError:`; `except (json.JSONDecodeError, UnicodeDecodeError) as e:`. `OSError` covers
  missing, directory, permission and disk errors; catch it only when every one of those means the same thing.
- Chain: `raise ConfigError(f"{path}: {key} must be ...") from e`; `from None` only when the cause adds nothing.
- Custom types: `class ConfigError(ValueError)` if callers already catch `ValueError`; otherwise `Exception`.
- Validation: check type exactly when it matters (`isinstance(v, bool)` before `int`, since `True` is an `int`).
- Top level: `logging.exception("...")` inside the handler logs the trace; then exit non-zero (`sys.exit(1)`).
- Tests: `with self.assertRaisesRegex(ConfigError, "timout"):` / `pytest.raises(ConfigError, match="port")`.
- Cleanup: `with` blocks; `tempfile.NamedTemporaryFile(dir=..., delete=False)` then `os.replace` for atomic writes.

## JavaScript / TypeScript

- Narrow: `catch (e) { if (e.code !== 'ENOENT') throw e; ... }`; `e instanceof SyntaxError` for `JSON.parse`.
- Chain: `throw new ConfigError(msg, { cause: e })` (Node 16.9+); custom `class ConfigError extends Error {}` with
  `this.name = 'ConfigError'`.
- Promises: every promise awaited or returned; no `.catch(() => {})`; `process.on('unhandledRejection')` only to log
  and exit. Express/Koa: pass errors to `next(err)`; one error middleware maps types to status codes.
- Tests: `expect(() => load(p)).toThrow(/timout/)`; async `await expect(p).rejects.toThrow(ConfigError)`.

## Go

- Never `_ = err` or `if err != nil { return nil }` for a real failure. Return it with context:
  `return fmt.Errorf("load settings %s: %w", path, err)`.
- Check kinds: `errors.Is(err, fs.ErrNotExist)`, `errors.As(err, &syntaxErr)`. Sentinel errors: `var ErrNotFound = errors.New("not found")`.
- `defer f.Close()` after the error check; for writes, check the error from `Close`.
- Tests: `if !errors.Is(err, ErrBadConfig) { t.Fatalf(...) }`.

## Rust

- `?` with `thiserror` enums in libraries, `anyhow::Context` (`.with_context(|| format!("reading {path}"))`) in
  applications. `unwrap()`/`expect()` only for invariants, with a message saying which.
- `unwrap_or_default()` on a `Result` silently drops the error: same rule as a silent default.
- Match `io::ErrorKind::NotFound` for the optional-file case.

## Java / Kotlin

- Catch specific types (`NoSuchFileException`, `JsonParseException`); `catch (Exception e)` only at the top level.
- Wrap with the cause: `throw new ConfigException("app.yaml: unknown key 'timout'", e)`.
- try-with-resources for every `Closeable`. Don't `return null` for failure; throw or return `Optional` for absent.
- Kotlin: `runCatching { }` swallows everything, including cancellation; avoid it around coroutine code.

## Swift

- `throws` with an `enum ConfigError: Error, CustomStringConvertible` carrying the file and key.
- `try?` turns every error into `nil`: same as a silent default; use `do { } catch CocoaError.fileReadNoSuchFile { }`.
- `defer` for cleanup; `Result` when the error must cross an async callback boundary.

## Shell

- `set -euo pipefail`; check commands whose failure matters (`cmd || { echo "cmd failed: ..." >&2; exit 1; }`).
- `|| true` is a swallowed error: keep it only where failure is expected, with a comment.
- Errors to stderr, non-zero exit codes, `trap 'rm -f "$tmp"' EXIT` for cleanup.
