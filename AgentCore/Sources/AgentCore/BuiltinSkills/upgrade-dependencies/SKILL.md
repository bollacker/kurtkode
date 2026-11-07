---
name: upgrade-dependencies
description: Use when bumping or upgrading a library, framework or toolchain version, updating a lockfile, or fixing npm audit, pip-audit or Dependabot alerts. Handles every breaking change. Not for broken builds (fix-build-and-ci).
---

# Upgrade dependencies

Move to a newer version of a dependency with every breaking change found and handled, including the ones no test
catches, and the app behaving as before unless the user asked for the new behavior.

## Fast path

For a patch or minor bump whose changelog lists no breaking or behavior changes: upgrade it with the package
manager, run the tests and build, report. You still read the changelog entries; that is the whole check.

## Steps

1. **Inventory.** Find where the dependency is declared and locked (manifest, lockfile, vendor folder, version
   file), the version in use, and the target. To list outdated or vulnerable packages, see
   `references/commands.md`. If asked to "update everything", plan one dependency (or one tightly coupled group,
   like a framework and its plugins) per round.

2. **Baseline.** Run the tests, build and linters before changing anything and keep the results. Failures that
   exist now are not yours; note them so you don't chase them later.

3. **Read the changelog for every version between current and target**, not only the target's headline: the
   package's `CHANGELOG`/`HISTORY`/`NEWS` file (in `node_modules/<pkg>/`, site-packages, the vendored copy, the
   module cache), its release notes, and its migration guide for a major version. Write the list:
   - **loud** changes: removed or renamed APIs, moved modules, changed signatures (errors will show them);
   - **silent** changes: new defaults, changed meaning of an argument or return value, different rounding, ordering,
     escaping or time zones (nothing fails; output changes);
   - dropped runtime versions, new peer dependencies, deprecations you will hit next time.

4. **Find every use of each changed item.** `grep -rn` the names (and import paths) across the code, including
   scripts and templates. For each call site, decide: affected or not, and why. Silent changes affect every call
   that relies on the old default or meaning, even if it looks harmless.

5. **Pin today's behavior where tests don't cover it.** For each affected call site of a silent change, add a test
   asserting the current output, and run it on the old version (it must pass there).

6. **Upgrade that one dependency** with its package manager, letting the tool rewrite the lockfile
   (`references/commands.md`). For a vendored copy, point the project at the new copy.

7. **Adapt the call sites.** Change your code to the new API. Keep the old behavior by passing explicitly what the
   old default or meaning did (`strict=False`, `tz=UTC`, an adjusted limit), unless the user wants the new behavior. Use the migration guide's
   replacements rather than inventing shims.

8. **Verify.** Run the tests (including step 5's), build and linters; compare with the baseline. Re-run the
   vulnerability audit if security was the reason. Then start the next dependency at step 3.

## Rules

- **Don't trust green tests as proof the upgrade is safe.** Tests check what someone thought to test; the
  changelog says what changed. "The tests pass, so nothing broke" is the excuse this blocks.
- **Don't edit the dependency's code** (`node_modules`, `vendor/`, site-packages) to bring old behavior back: the
  next install undoes it and nobody will know. Change your code, or stay on the old version and say why.
- **Don't upgrade more than asked in one step** (`npm update`, `cargo update`, `uv lock --upgrade` with no package
  name). A failure then has many suspects.
- **Don't hand-edit lockfiles** or silence resolver conflicts with `--force`, `--legacy-peer-deps` or
  `npm audit fix --force`; they install other major versions without telling you.
- **Don't jump past the requested version**, and don't downgrade or remove other packages to make the resolver
  happy without saying so.
- For an advisory, prefer the smallest version that fixes it. If none exists, say so and describe the exposure
  (is the vulnerable function reachable from our code?) instead of forcing an unrelated major upgrade.

## When no one can answer

Keep existing user-visible behavior (URLs, output formats, stored data, defaults) unless the request says to adopt
the new one; record each choice. If a breaking change has no behavior-preserving path, take the closest one and
list it under "behavior changes" in the report. Stop and report instead of upgrading if the target needs a runtime
or platform the project doesn't support, or a data migration you can't test.

## Done means

A short report with:
- **versions**: each dependency, from → to, and where it is pinned;
- **breaking changes**: a table of change | loud or silent | affects us? | call sites (file:line) | what we did;
- **evidence**: tests, build and lint before and after (commands and results), the audit result if relevant;
- **behavior changes** that remain, and deprecations to handle next time.
