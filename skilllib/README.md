# skilllib: software-development skills for coding agents

30 Agent Skills (`SKILL.md` folders) for the work a coding agent does in a repository: understanding code, planning,
building, testing, debugging, reviewing, releasing. Written for kurtkode, portable to Claude Code, Codex, opencode,
Gemini CLI, Cursor and Copilot (front matter is only `name` and `description`). Every skill has tests, and the
library was measured against a no-skill baseline on three models (`RESULTS.md`).

| File | What it is |
|---|---|
| `TAXONOMY_FINAL.md` | **The final taxonomy**: every skill, what it covers, and what the tests showed |
| `RESULTS.md` | How the skills were tested and what was measured |
| `skills/` | The 30 skills |
| `install/AGENTS-snippet.md` | Four lines for a project's `AGENTS.md`/`CLAUDE.md`; skills load far more often with it |
| `packs/INDEX.md` | Vendor knowledge packs (React, Postgres, Terraform, …) to add per project instead of copying |
| `STYLE.md` | How a skill in this library is written and tested |
| `eval/` | The test harness, the 31 task cases and the results |
| `TAXONOMY_v0.md`, `EVALUATION.md`, `TAXONOMY_v1.md` | How we got here: first taxonomy, review of existing skills, target taxonomy |
| `reports/`, `research_notes/` | The research on existing skills and on skill evaluation |

## Install

**kurtkode: nothing to do.** The skills ship inside kurtkode as its built-in skills (the folder `skills/` is a link
to `AgentCore/Sources/AgentCore/BuiltinSkills`, the resource the app and CLI bundle), and when any skill is offered
the system prompt says to check them first (`AgentCore/Sources/AgentCore/Prompts/skills.md`, the same effect as the
AGENTS.md snippet below). A project's or user's skill of the same name replaces a built-in one. Settings → Generation
→ Agent → "Built-in skills" turns them off; so does `kurtkode --no-builtin-skills`. `/skills` lists them. For small
and local models, the **skill router** (same Settings section, "Skill router"; `--skill-router auto|on|off`) asks the
model which skill fits each new request and puts that skill's instructions in front of it: Qwen 3.5 9B went from
loading the right skill 10% of the time to 94%.

**Other agents**: copy (or symlink) the skills where the agent looks for them, for one project or for every project:

```bash
cp -R skills/* <project>/.agents/skills/        # kurtkode, Codex, opencode, Gemini CLI, Cursor, Copilot
cp -R skills/* <project>/.claude/skills/        # Claude Code
cp -R skills/* ~/.agents/skills/                # all projects (kurtkode also reads ~/.kurtkode/skills, ~/.claude/skills)
```

Then add `install/AGENTS-snippet.md` to the project's `AGENTS.md` (or `CLAUDE.md`). Measured on Gemini 3.6 Flash,
it raised how often the right skill loads from 66% to 92% (it never made a near miss load the wrong skill). Without
it, models tend to start exploring files and never load a skill.

Add packs from `packs/INDEX.md` only for the stacks a project uses; keep the total skill list short.

## Run the tests

```bash
cd eval
python3 validate_case.py --all                     # every case: check fails on the fixture, passes on the reference
python3 skilleval.py --mode trigger --model "Google Gemini:gemini-3.6-flash" --agents-md ../install/AGENTS-snippet.md
python3 skilleval.py --mode task --arms baseline,forced,skills,control --trials 3 --skills code-review \
    --model "Google Gemini:gemini-3.6-flash" --judge "Google Gemini:gemini-4-argon" --agents-md ../install/AGENTS-snippet.md
python3 analyze.py results/<file>.jsonl            # arms side by side
python3 summarize.py                               # one row per skill across all results
python3 ../skills/write-skills/scripts/validate_skill.py ../skills/*   # lint the library
```

The harness drives the kurtkode CLI (`kurtkode -p`) in a fresh git copy of each fixture; any `endpoint:model` kurtkode
knows works (`bang:qwen/qwen3.5-9b` is a LAN LM Studio). Test sessions go to the Trash afterwards; project folders
stay in `eval/runs/` (git-ignored) so a fixed check can re-score old runs (`rescore.py`).

## Credits

The skill text is ours. Designs we learned from (no text copied): obra/superpowers (systematic debugging, TDD,
verification, receiving review, plans), Anthropic's `/code-review`, `/security-review` and skill-creator, Trail of
Bits' fp-check and audit-context-building, OpenAI's gh-fix-ci, mattpocock's handoff and grill-me, igmarin's
refactor-code. The test method combines Anthropic's skill-creator evals, superpowers' pressure tests and the
WebDev-Skills-Bench control arm (details and links in `reports/`).
