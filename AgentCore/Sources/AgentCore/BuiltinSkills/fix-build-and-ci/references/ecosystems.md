# Reproducing builds per stack, and CI-only causes

Read this in step 3 of SKILL.md, when you need the clean-reproduce commands for a stack or the failure does not
reproduce locally.

## Getting the CI log

| CI | Where the failing log is |
|---|---|
| GitHub Actions | `gh run list --branch <b> --limit 5`, then `gh run view <id> --log-failed` (or `--log > ci.log`); `gh pr checks <pr>` lists failing checks. Without `gh`: the run page, "Download log archive". |
| GitLab | `glab ci view` / `glab ci trace <job-id>`, or the job page's raw log |
| Jenkins, Buildkite, CircleCI | the job's raw/console log; save it to a file and run `first_error.py` on it |

Check the job's header for the runner image and tool versions (setup steps print them).

## Clean reproduce, per stack

| Stack | Clean install from the lockfile | Build / check / test (typical CI) | Clear caches and outputs |
|---|---|---|---|
| npm | `npm ci` | `npm run build`, `npm run lint`, `npx tsc --noEmit`, `npm test` | `rm -rf node_modules dist .next` |
| pnpm / yarn | `pnpm install --frozen-lockfile` / `yarn install --immutable` | as above with `pnpm` / `yarn` | `rm -rf node_modules` |
| pip | `python -m venv .venv && .venv/bin/pip install -r requirements.txt` | `ruff check .`, `mypy .`, `pytest` | `rm -rf .venv build dist *.egg-info .mypy_cache` |
| uv | `uv sync --frozen` | `uv run ruff check`, `uv run pytest` | `rm -rf .venv` |
| poetry | `poetry install --sync` | `poetry run pytest` | `poetry env remove --all` |
| cargo | `cargo fetch --locked` | `cargo build --locked`, `cargo clippy -- -D warnings`, `cargo test` | `cargo clean` |
| go | `go mod download && go mod verify` | `go build ./...`, `go vet ./...`, `go test ./...` | `go clean -cache -testcache` |
| swift (SPM) | `swift package resolve` | `swift build`, `swift test` | `rm -rf .build` |
| xcode | — | `xcodebuild -scheme <S> -destination '<d>' build test` | delete DerivedData for the project |
| maven | `mvn -B dependency:go-offline` | `mvn -B verify` | `mvn clean` |
| gradle | — | `./gradlew build` (`--stacktrace` for detail) | `./gradlew clean`, `--no-build-cache` |
| make / cmake | — | `make` (`make -j1` to make the first error appear in order) | `make clean`, or a fresh build dir |

Parallel builds interleave output: re-run with one job (`make -j1`, `cargo build -j1`, `pytest -p no:xdist`) when the
first error is hard to read.

## Fails in CI, passes locally: the usual causes

| Cause | How to check |
|---|---|
| A file exists locally but is not committed (or is ignored) | `git status --ignored`; clone into a temp dir and build there |
| Lockfile out of date or not used | CI uses `npm ci`/`--frozen`/`--locked`; run the same |
| Different tool or runtime version | compare `node --version`, `python3 --version`, `rustc --version`, `go version` with the CI header |
| Case-sensitive file system (Linux CI, macOS laptop) | import paths whose case differs from the file name |
| Missing environment variable or secret | grep the code for the variable; forks and PRs from forks get no secrets |
| Generated file stale or not generated in CI | the step that generates it, and whether it ran before the failing step |
| Time zone, locale, CPU count | `TZ=UTC`, `LC_ALL=C`, run with CI's worker count |
| Cache restored from an older run | re-run without cache; check the cache key includes the lockfile hash |

## Suppression forms to look for in your own diff before you finish

`# noqa`, `# type: ignore`, `# pylint: disable`, `// eslint-disable…`, `// @ts-ignore`, `// @ts-expect-error`,
`#[allow(...)]`, `@SuppressWarnings`, `//nolint`, `|| true`, `set +e`, `continue-on-error: true`, `allow_failure`,
`-k 'not …'`, `--ignore`, `.skip`, `xit`, `@pytest.mark.skip`, `t.Skip`, raised coverage or timeout limits.
None of these belong in the fix unless the user asked for them.
