---
name: release
description: Use when cutting or preparing a release (bumping the project's version, writing the changelog or release notes, tagging, publishing to npm or PyPI). Same version everywhere. Not for dependency bumps (upgrade-dependencies).
---

# Release

Produce a release commit and tag where the version is the right one by semver, is the same in every place it
lives, and the changelog tells users what changed for them.

## Fast path

If the version lives in one file and the changes since the last tag are few and clearly labeled, the skill reduces
to steps 2, 4 and 7: classify the commits, run `find_versions.py`, commit and tag. Still never push or publish
unasked.

## Steps

1. **Learn how releases are done here.** `git describe --tags --abbrev=0` gives the last release tag. Look at it:
   tag format (`v1.2.3` or `1.2.3`), annotated or not (`git cat-file -t <tag>`), the previous release commit's
   message and files (`git show <tag> --stat`), the CHANGELOG format, and any release tooling (a `release` target
   in the Makefile, `npm version`, bump-my-version, release-please, cargo-release). Follow what exists. Make sure
   the tree is clean and the tests pass before starting.

2. **List and classify the changes since the last tag.**
   `git log --no-merges --format='%h %s' <last-tag>..HEAD`
   Sort each commit into user-facing (Added, Changed, Deprecated, Removed, Fixed, Security) or not (chores, CI,
   build, tests, refactors, internal docs). The prefix is a hint, not proof: read the diff (`git show --stat <sha>`,
   then the code) of every commit without a prefix or whose effect is unclear. Mark breaking changes: `type!:`, a
   `BREAKING CHANGE:` footer, a removed or renamed public API, a changed default or output format.

3. **Choose the version by semver.** Breaking change → major (while at 0.x, minor). Otherwise any new feature →
   minor. Only fixes → patch. If the user named a version, use it, and say so if it contradicts the changes.

4. **Find every place the version lives.**
   `python3 <skill folder>/scripts/find_versions.py`
   `DECLARED` lines are version fields of known files; change them all (with the ecosystem's bump command when
   there is one: `references/ecosystems.md`). `MENTION` lines are every other line with the same string: decide
   each one. Change those that are this project's version (install commands, docs, a version constant, a badge);
   leave those that only look the same (a dependency's version bound, a file-format or API version, test data).

5. **Write the changelog entry** in the file's existing format and order: the new version and today's date at the
   top, user-facing changes grouped by kind, each written for a user ("`export` can now write CSV"), not
   copied commit subjects. If there is an "Unreleased" section, turn it into the release section as the file's
   convention does. Leave older sections untouched.

6. **Verify.** `find_versions.py --expect <new>` must exit 0, and every remaining `MENTION` of the old version must
   be one you chose to keep. Run the tests and the build; check the built thing reports the new version
   (`--version`, package metadata, `npm pack --dry-run`).

7. **Commit, then tag that commit.** One release commit in the repository's message style, then the tag in the
   existing format: `git tag -a v2.1.0 -m "<name> 2.1.0"` (lightweight only if previous tags are). Check with
   `git show <tag> --stat` that the tag holds the bumped files.

8. **Push and publish only if asked** (`git push origin <branch> <tag>`, `npm publish`, `twine upload`,
   `cargo publish`). Otherwise list these commands in the report.

## Rules

- **Don't search-and-replace the version string across the repository.** The same digits appear in dependency
  bounds, format versions and test data; a blanket replace changes them silently.
- **Don't paste the git log as the changelog.** Chores, CI, refactors and test commits mean nothing to users; one
  line per user-visible change, in their words.
- **Don't tag before the bump is committed.** The tag must point at the commit that contains the release.
- **Don't move, delete or reuse a tag or a published version number.** Registries refuse reuse and users may already
  depend on the old one; make a new patch release instead.
- **Don't push, publish or create a hosted release unasked.** It is public and can't be taken back.

## When no one can answer

Pick the version semver gives from the commits and write the reason in the report. If you can't tell whether a
change breaks users after reading its diff, choose the higher bump and say why. Use today's date and the existing
conventions for tag format and commit message. Do everything local (bump, changelog, commit, tag) and stop before
anything public; report the commands to run.

## Done means

A release commit and a tag on it, locally, and a short report with:
- **version** and the semver reason (e.g. "minor: adds CSV export; no breaking changes");
- **files changed** for the version, and the look-alike mentions deliberately left unchanged, with why;
- **changelog entry** as written;
- **evidence**: `find_versions.py --expect <new>` result, tests and build result;
- **not done**: push and publish commands, unless the user asked for them.
