---
name: savework
description: Recap the current work session into a short markdown file under .history/ in the project root, so a future Claude session with no memory of this one can get oriented fast. Invoke this automatically — without being asked — right after a code change, config/infra change, decision, root-caused bug, fix, or discovery lands that a future session would need to know about. Also invoke when the user explicitly says "savework", "recap this session", or asks to save/log the work done. Creates .history/ and its CLAUDE.md automatically if missing.
---

# Save Work Session Recap

Write a short, cheap-to-read recap of what just happened in this project, for a future Claude session to read before doing anything else.

## When to run this automatically

Run it without being asked, right after any of the following lands in the current project:
- A code, config, or infra change a future session would need to know about
- A decision made among alternatives (why X was chosen over Y)
- A bug root-caused, a fix applied, or a workaround adopted
- A discovery about the codebase/infra that wasn't already documented anywhere
- Before wrapping up a working session, if nothing was recapped yet

Skip it for pure Q&A, read-only investigation with no lasting conclusion, or trivial one-line edits.

## Steps

1. **Find the project root.** Use `git rev-parse --show-toplevel` if inside a git repo; otherwise use the workspace/project root the user is working in. Never use a subdirectory or a scratch/tmp dir.

2. **Ensure `.history/` exists.**
   - Create `<project-root>/.history/` if it doesn't exist.
   - If `<project-root>/.history/CLAUDE.md` doesn't exist, create it by copying this skill's `templates/history-CLAUDE.md` verbatim.

3. **Build the filename** — pattern `{epoch_seconds}_{title}.md`:
   - Get the epoch: `date +%s`.
   - Title: ≤50 characters, lowercase kebab-case (`a-z0-9-` only), summarizing this session's work in a few words.
   - Example: `1755678900_fix-jwt-refresh-race.md`.
   - On the rare same-second collision, append `-2`, `-3`, … to the title.

4. **Write the content** — target ~500 characters total; exceed only when genuinely required (e.g. several unrelated decisions in one session), never pad:
   - **Line 1**: date + time only, short — output of `date '+%Y-%m-%d %H:%M'`. Nothing else on that line.
   - **Then**: a few short plain sentences — what changed, why (if non-obvious), and anything a future session must not have to re-derive (a decision, a gotcha, an open/blocked item).
   - No headers, no bullet ceremony, no restating what's already obvious from the code, git log, or diff.

5. **Write the file** to `<project-root>/.history/{epoch}_{title}.md`. Confirm the path back to the user in one line.

## Example

`.history/1755678900_fix-jwt-refresh-race.md`:
```
2026-08-20 17:05
Fixed a race in JWT refresh: two tabs refreshing simultaneously both got new tokens but only one was persisted, logging the other tab out. Deduped refresh via a shared in-flight promise in src/auth/refresh.ts. Chose in-memory dedup over a lock file — no cross-process case here.
```
