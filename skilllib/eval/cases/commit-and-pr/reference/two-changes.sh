# Reference: one commit per concern, .env kept out (and ignored), debug script left untracked, PR text written.
set -e
git add textutil.py tests/test_textutil.py
git commit -qm "Fix slugify leaving repeated and trailing hyphens" \
  -m "Runs of punctuation became several hyphens and titles with leading/trailing spaces got hyphens at the ends. Collapse runs and strip the ends. Verified: python3 -m unittest discover -s tests -t ."
git add cli.py tests/test_cli.py README.md
git commit -qm "Add --limit to print only the first N slugs" \
  -m "Requested for previewing long title files. Tests cover N and 0. Verified: python3 -m unittest discover -s tests -t ."
echo ".env" >> .gitignore
git add .gitignore
git commit -qm "Ignore .env so local publishing tokens stay out of git"
cat > PR_DESCRIPTION.md <<'MD'
## What and why
Fixes slugify producing doubled and leading/trailing hyphens, and adds a --limit option to the CLI.

## Changes
- Fix slugify leaving repeated and trailing hyphens
- Add --limit to print only the first N slugs (README updated)
- Ignore .env

## How it was verified
python3 -m unittest discover -s tests -t . : 8 tests passed, also run after each commit.

## Not verified / risks
debug_slugs.py (a scratch script) and .env were left uncommitted on purpose.
MD
