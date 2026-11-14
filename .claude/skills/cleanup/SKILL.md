---
name: cleanup
description: Cleanup and maintainability review. Use only when the user asks for a cleanup.
---

## CLEANUP
Report only. Don't change code yet.
- Read CLAUDE.md and docs/ARCHITECTURE.md. In a fork, review only my code.
- Find cheaply: run the check command, plus a dead-code tool for the language (e.g. knip for JS/TS, vulture for Python) without adding it to dependencies, plus the package manager's security audit (report high/critical only). Subagents per area only if there are 50+ source files.
- Before calling anything unused, search its name everywhere: config, routes, strings, native/platform files, tests. Loaded dynamically means not dead.
- Look for: dead code (files, functions, components, routes, APIs, variables, imports, dependencies); duplicate logic; overly complex code; legacy or disconnected code; redundant database/API calls; outdated or vulnerable dependencies; the 3 most important behaviors with no test; code that's hard to follow or test because one idea is spread across many files or parts are tangled together; other tech debt.
- Keep the docs cheap and true: fix ARCHITECTURE.md where it no longer matches the code; move completed milestones from PLAN.md to docs/DONE.md as one line each; merge duplicate lessons in docs/LESSONS.md; cut CLAUDE.md lines you already follow without being told.
- Overwrite docs/CLEANUP.md with a table sorted by value vs. risk: issue | where | why unnecessary | impact | risk | confidence. Max 30 rows; group trivial items.
- Add cleanup milestones to PLAN.md: safest, high-confidence first, one category each, done when the check command passes and the app runs. Low confidence goes under "Ask me first". No tests in an area: add a smoke-test milestone first. Update "Last cleanup".
- Summarize in at most 10 bullets. Be aggressive but safe: nothing is deleted until it's an approved milestone and the checks pass afterward.
