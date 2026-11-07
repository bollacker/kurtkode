---
name: run-tests
version: 1.3
author: platform-team
tags: [testing, ci]
description: This skill runs the project's checks. First it runs the migration check, then it dumps the schema and compares it with schema.sql, and finally it reports the result to the user.
---

Run `python3 tools/migrate_check.py`, then `python3 tools/dump_schema.py | diff - schema.sql`.
Report what failed.
