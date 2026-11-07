# Knowledge packs: when to add which

The core library (`skills/`) holds process and tool skills that apply to any project. Stack knowledge that vendors
maintain is better taken from them than rewritten: they track new versions, and the research found generic language
"expert" skills add little. This index says which pack fits which project. Install a pack into the project
(`.agents/skills/` or `.claude/skills/`), not globally, so the skill list stays short (selection accuracy falls as
the list grows, sooner for small models).

Packs aren't vetted by this library's tests. Read a pack's SKILL.md and every script it ships before installing it
(skills are a prompt-injection path).

Vercel's measurement suggests knowledge packs are often not picked up from their description alone. After installing
one, add a line to the project's `AGENTS.md` / `CLAUDE.md` naming it, e.g. "For React components, load the
react-best-practices skill first."

| If the project uses … | Add | Source | License |
|---|---|---|---|
| React, Next.js | react-best-practices; web-design-guidelines for UI and accessibility | github.com/vercel-labs/agent-skills | MIT |
| Postgres / Supabase (schema, queries, indexes, locks, RLS) | supabase-postgres-best-practices | github.com/supabase/agent-skills | MIT |
| Terraform, Packer | the HashiCorp skills for the tools in use | github.com/hashicorp/agent-skills | MPL-2.0 |
| Modern Python tooling (uv, ruff, ty) | modern-python | github.com/trailofbits/skills | CC-BY-SA-4.0 |
| C++ 20/23 and compiler hardening | modern-cpp | github.com/trailofbits/skills | CC-BY-SA-4.0 |
| SwiftUI | swiftui-pro | github.com/twostraws/SwiftUI-Agent-Skill | MIT |
| Kotlin | the JetBrains Kotlin skills (incubator) | github.com/Kotlin/kotlin-agent-skills | check |
| A web app to test in a browser | webapp-testing (Playwright, server lifecycle script) | github.com/anthropics/skills | Apache-2.0 |
| UI built from a design | frontend-design | github.com/anthropics/skills | Apache-2.0 |
| Fuzzing, property-based tests, sanitizers | the fuzzing and property-based-testing skills | github.com/trailofbits/skills | CC-BY-SA-4.0 |
| Static analysis (Semgrep, CodeQL, SARIF) | semgrep, codeql, sarif-parsing | github.com/trailofbits/skills | CC-BY-SA-4.0 |
| A deep security audit or supply-chain review | differential-review, fp-check, supply-chain-risk-auditor | github.com/trailofbits/skills | CC-BY-SA-4.0 |
| GitHub Actions, with the `gh` CLI | gh-fix-ci | github.com/openai/skills (moving to openai/plugins) | Apache-2.0 |
| Cloudflare Workers, Stripe, Expo, Google Cloud, Azure | the vendor's own skills | the vendor's skills repository | vendor |
| Parallel branches in git worktrees | using-git-worktrees | github.com/obra/superpowers | MIT |

The core skills cover the process side of the same work (for example `security-review` for a change, `fix-build-and-ci`
for any CI); a pack adds the stack-specific rules.
