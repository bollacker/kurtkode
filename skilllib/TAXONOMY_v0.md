# Software development skills: taxonomy v0 (first principles, before research)

Written 2026-10-25 before looking at what exists. Purpose: a coverage frame to map existing skills onto and to find gaps.
Each skill is a SKILL.md folder (Agent Skills format) that kurtkode, Claude Code, opencode and Codex can load.

Three kinds of skill, which differ in how they are written and tested:

- **Process** (P): how to approach a class of task; general across languages (debugging, TDD, code review).
- **Knowledge** (K): reference material for a domain (a language's idioms, a framework, SQL dialects).
- **Tool** (T): a procedure built around scripts or commands the skill ships or names (bisect, profiling, release).

## A. Understanding code
1. Codebase orientation: map a repo's layout, entry points, build, tests, conventions (P)
2. Tracing a behavior: follow a feature or data value through the code (P)
3. History archaeology: why code is the way it is (blame, log -S, PRs) (T)
4. Dependency and impact analysis: who calls this; what breaks if it changes (P)
5. Reading an unfamiliar language or framework quickly (P/K)

## B. Requirements and design
6. Clarifying requirements: questions, acceptance criteria, scope (P)
7. Brainstorming / options analysis with a recommendation (P)
8. Design doc / RFC / ADR writing (P)
9. API design (REST, RPC, library interfaces, versioning) (K)
10. Data modeling and schema design (K)
11. Planning and task breakdown: an executable plan with checkpoints (P)

## C. Implementation
12. Feature implementation loop: plan, small steps, verify each (P)
13. Test-driven development (P)
14. Refactoring safely: behavior-preserving steps under tests (P)
15. Error handling and input validation (K)
16. Concurrency and async correctness (K)
17. Language idioms packs: Python, TypeScript/JS, Go, Rust, Swift, Java/Kotlin, C/C++, shell (K)
18. Framework packs: web frontend (React …), backend (Django, Rails, Express …), mobile (K)
19. Writing CLI tools and scripts (K)
20. SQL and query writing (K)
21. Regular expressions and text processing (K)

## D. Testing and quality
22. Writing unit tests (good tests, not coverage padding) (P)
23. Integration and end-to-end tests (P/K)
24. Fixing failing / flaky tests (P)
25. Property-based and fuzz testing (K)
26. Test coverage gap analysis (T)
27. Static analysis, linting, type checking setup and fixes (T)
28. Code review: reviewing a diff or PR for bugs (P)
29. Receiving review: responding to and applying review comments (P)
30. Verification before claiming done (P)

## E. Debugging
31. Systematic debugging: reproduce, hypothesize, isolate, fix, confirm (P)
32. Root-cause analysis (beyond the symptom) (P)
33. Bisecting regressions (git bisect, delta debugging) (T)
34. Reading stack traces, logs, core dumps (K)
35. Performance profiling and optimization (T)
36. Memory leaks and resource exhaustion (T)
37. Concurrency bugs: races, deadlocks (P/K)

## F. Security
38. Secure code review (OWASP classes) (P/K)
39. Secrets handling and leak detection (T)
40. Dependency vulnerability audit and upgrade (T)
41. Threat modeling (P)
42. AuthN/AuthZ implementation (K)

## G. Data and persistence
43. Database migrations (safe, reversible, zero-downtime) (P/K)
44. Query performance (indexes, EXPLAIN) (K)
45. Data pipelines and ETL correctness (K)

## H. Dependencies, build, packaging
46. Dependency upgrades and framework/version migrations (P)
47. Build system debugging (P/K)
48. Packaging and releasing (versioning, changelog, tags, publishing) (T)
49. Reproducible dev environment setup (T)

## I. Version control and collaboration
50. Commit hygiene: atomic commits, messages (P)
51. Branching, rebasing, merge conflict resolution (T)
52. Pull request preparation and description (P)
53. Changelogs and release notes (P)

## J. Delivery and operations
54. CI configuration and fixing CI failures (T)
55. Containers (Dockerfiles, compose) (K)
56. Deployment and rollback (P)
57. Observability: logging, metrics, tracing (K)
58. Infrastructure as code (Terraform …) (K)
59. Incident response and postmortems (P)

## K. Documentation
60. README and getting-started docs (P)
61. API reference and docstrings (P)
62. Architecture docs and diagrams (P)
63. Code comments (when and what) (P)

## L. Maintenance and evolution
64. Legacy code: characterization tests, then change (P)
65. Large-scale codemods / mechanical changes (T)
66. Dead code and tech-debt assessment (P)
67. Performance regression guarding (T)

## M. Frontend and UI
68. Accessibility (K)
69. Implementing a UI from a design; visual verification (P/T)
70. Responsive layout and CSS debugging (K)

## N. Agent working practice (meta)
71. Asking clarifying questions vs proceeding on defaults (P)
72. Context management: what to read, when to summarize (P)
73. Delegating to subagents (P)
74. Handoff notes and session journals (P)
75. Working in git worktrees / parallel branches (T)
76. Writing and testing new skills (P)
77. Estimating effort and reporting status honestly (P)
