# Version bump, build and publish commands per ecosystem

Read this in steps 4, 6 and 8 of SKILL.md. Some bump tools commit and tag by default (`npm version`, `cargo release`,
`bump-my-version` with `commit = True`); the forms below don't, so step 7 makes the one commit and tag.

| Ecosystem | Where the version lives | Bump without committing | Build / check the artifact | Publish (only if asked) |
|---|---|---|---|---|
| npm / pnpm / yarn | `package.json` (and the root entry of `package-lock.json`) | `npm version 2.1.0 --no-git-tag-version` (updates the lockfile too); `pnpm version`, `yarn version` | `npm pack --dry-run` (shows version and files) | `npm publish` (`--tag next` for pre-releases) |
| Python (PEP 621) | `pyproject.toml` `[project] version`, often `pkg/__init__.py` `__version__`; dynamic versions come from a file or git tags (setuptools-scm, hatch-vcs) | edit the field(s); `uv version 2.1.0` / `uv version --bump minor` (recent uv); `hatch version minor`; `poetry version minor` | `python -m build`, then `twine check dist/*` | `twine upload dist/*` / `uv publish` / `poetry publish` |
| Rust | `Cargo.toml` `[package] version` (workspace: `[workspace.package]`); `Cargo.lock` own entry | edit, then `cargo update -p <crate> --offline` or `cargo build` to refresh the lockfile; `cargo set-version` if cargo-edit is installed | `cargo package --list`, `cargo publish --dry-run` | `cargo publish` |
| Go | no version in files: the git tag is the version (`vX.Y.Z`; major ≥2 needs `/vN` in the module path) | — | `go build ./...`, `go test ./...` | push the tag |
| Swift (SPM) | git tag only (`2.1.0`, often without `v`); apps: `MARKETING_VERSION` in the Xcode project, `CFBundleShortVersionString` | `agvtool new-marketing-version 2.1.0` (Xcode projects) | `swift build -c release` | push the tag |
| Maven | `pom.xml` `<version>` (and child modules) | `mvn versions:set -DnewVersion=2.1.0 -DgenerateBackupPoms=false` | `mvn -B verify` | `mvn deploy` |
| Gradle | `version` in `build.gradle(.kts)` or `gradle.properties` | edit | `./gradlew build` | `./gradlew publish` |
| Ruby | `lib/<gem>/version.rb`, `Gemfile.lock` own entry | edit, `bundle install` | `gem build *.gemspec` | `gem push` |
| Helm | `Chart.yaml` `version` (chart) and `appVersion` (app): different meanings | edit | `helm lint`, `helm package` | registry push |

Places outside manifests that often carry the version: `CITATION.cff`, docs install snippets (`pip install x==`,
`npm i x@`), README badges, Dockerfile `LABEL version`, `--version` strings hard-coded in the CLI, Sphinx
`conf.py`, OpenAPI `info.version` (the API's version, which may differ from the package's), snapcraft/flatpak
manifests, Homebrew formulas in the repo.

## Changelog conventions

- Keep a Changelog: `## [2.1.0] - 2026-05-14`, groups `### Added / Changed / Deprecated / Removed / Fixed /
  Security`, an `## [Unreleased]` section on top, link references at the bottom (`[2.1.0]: …compare/v2.0.3...v2.1.0`)
  that need a new line too.
- Conventional-commit-generated changelogs (release-please, semantic-release, git-cliff): run the configured tool
  instead of writing by hand, then read and correct its output.
- GitHub release notes: same content as the changelog section; create one only if asked
  (`gh release create v2.1.0 --notes-file notes.md`).

## Conventional commit types and what they mean for a release

`feat` → minor, user-facing (Added). `fix`, `perf` → patch, user-facing (Fixed / Changed). `type!` or a
`BREAKING CHANGE:` footer → major. `docs` → user-facing only for published documentation. `chore`, `ci`, `build`,
`test`, `refactor`, `style` → not in the changelog unless they change what users get (a dropped platform, a new
minimum runtime version: those are Changed or Removed, and may be breaking).
