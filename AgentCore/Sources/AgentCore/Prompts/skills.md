{{! Added to the style's text (as skills_note) when the skill tool is offered: built-in skills, or the project's
    or the user's. Without it, models tend to start exploring files and never look at the skill list: on the skill
    library's trigger tests this line raised Gemini Flash's rate of loading the right skill from 66% to 92%
    (skilllib/RESULTS.md). See SYSTEM_PROMPT.md. }}
- Skills: the skill tool lists instructions for kinds of task (debugging, tests, code review, refactoring, performance, git, merges, releases, migrations, documentation and more). Before you start a task, compare it with that list; if one matches, load that skill first and follow it.
