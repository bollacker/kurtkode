# Dependency commands per ecosystem

Read this in steps 1 and 6 of SKILL.md: to list outdated or vulnerable packages, find a package's changelog, and
upgrade exactly one package. "PKG" is the package name, "V" the target version.

| Ecosystem | Outdated | Vulnerabilities | Upgrade one package | Why is it installed |
|---|---|---|---|---|
| npm | `npm outdated` | `npm audit` | `npm install PKG@V` | `npm ls PKG`, `npm explain PKG` |
| pnpm | `pnpm outdated` | `pnpm audit` | `pnpm add PKG@V` (`pnpm update PKG` within range) | `pnpm why PKG` |
| yarn | `yarn outdated` / `yarn upgrade-interactive` | `yarn npm audit` | `yarn up PKG@V` | `yarn why PKG` |
| pip + requirements | `pip list --outdated` | `pip-audit` (if installed) | edit the pin to `PKG==V`, `pip install -r requirements.txt` | `pip show PKG` (Required-by) |
| uv | `uv pip list --outdated` | `uv pip audit`/`pip-audit` if available | `uv add 'PKG==V'` or `uv lock --upgrade-package PKG` | `uv tree --invert --package PKG` |
| poetry | `poetry show --outdated` | `pip-audit` on an export | `poetry add PKG@V` / `poetry update PKG` | `poetry show --tree` |
| cargo | `cargo outdated` (plugin) or read crates' versions | `cargo audit` (plugin) | edit `Cargo.toml`, then `cargo update -p PKG` | `cargo tree -i PKG` |
| go | `go list -m -u all` | `govulncheck ./...` | `go get PKG@vV && go mod tidy` | `go mod why -m PKG` |
| swift (SPM) | `swift package show-dependencies` | — | edit `Package.swift` requirement, `swift package update PKG` | `swift package show-dependencies` |
| maven | `mvn versions:display-dependency-updates` | OWASP `dependency-check` plugin | edit the version in `pom.xml` (or a property) | `mvn dependency:tree -Dincludes=G:A` |
| gradle | `./gradlew dependencyUpdates` (plugin) | dependency-check plugin | edit the version (or version catalog `libs.versions.toml`) | `./gradlew dependencyInsight --dependency PKG` |

Tools marked plugin or "if installed" may not exist; don't install them without asking. Without them, compare the
declared version with the newest one named in the package's changelog or registry page.

## Where the changelog is when you can't browse

- npm: `node_modules/PKG/CHANGELOG.md` (after installing the new version in a scratch copy), or `npm view PKG@V`
  for metadata; the repository URL is in `npm view PKG repository.url`.
- Python: the installed package's `*.dist-info/METADATA` (Project-URL lines), a `CHANGELOG`/`HISTORY` file in the
  sdist, or docs inside the package.
- Rust: `~/.cargo/registry/src/*/PKG-V/CHANGELOG.md`.
- Go: `$(go env GOMODCACHE)/PKG@vV/` (CHANGELOG, release notes in the repo).
- Vendored code: the copy itself; diff the two versions' public functions when the changelog is thin:
  `diff -ru vendor/PKG-OLD vendor/PKG-NEW`.

## Major-version moves with known traps

- A new major can change the import path (Go `/v2`, some npm scoped renames): grep imports, not just calls.
- Peer-dependency majors (React, a framework and its plugins) must move together: treat them as one round.
- A dropped runtime (Node, Python, Java version) needs the CI matrix and the `engines`/`requires-python`/
  `rust-version` fields changed too, or stop and ask if the project must keep supporting it.
- Lockfile format changes when the package manager itself is upgraded; do that in its own round.
