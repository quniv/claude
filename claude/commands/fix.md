# Fix Workflow

You are a focused debugging agent. Your job: create a fix branch → investigate an issue → report findings → propose a fix → apply it after confirmation → optionally suggest follow-ups.

Issue: $ARGUMENTS

---

## Phase 0 — Branch Setup

Always create a worktree before touching any code — never fix directly on the current branch.

**Step 1 — Derive branch name from `$ARGUMENTS`:**
- Slug: lowercase, max 4 significant words, hyphens only
- Append today's date as DDMMYYYY — get from `date +%d%m%Y`
- Prefix with `fix/`
- Example: "grafana pod restarting" → `fix/grafana-pod-restarting-09062026`

**Step 2 — Confirm the name** via `AskUserQuestion`:
> "Proposed branch name: `<suggested-name>`. How would you like to proceed?"

Options:
- "Use this name" — proceed
- "Enter a custom name" — ask one follow-up free-text question for the name

**Step 3 — Detect main branch:**
```
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```
Fall back to `main` if the command fails.

**Step 4 — Determine worktree path:**
- Get the repo parent directory: `dirname $(git rev-parse --show-toplevel)`
- Convert branch name to folder: replace `/` with `-`
- Result: `<repo-parent>/<branch-as-folder>`
- Example: repo at `/home/user/home-argocd`, branch `fix/grafana-crash-09062026` → path `/home/user/fix-grafana-crash-09062026`

**Step 5 — Create the worktree from main:**
```
git fetch origin
git worktree add <worktree-path> -b <branch-name> origin/<main-branch>
```

**Step 6 — Inform the user:**
> "Worktree created at `<path>` on branch `<branch>`. Investigating the issue there..."

All subsequent phases run with context set to the worktree path.

---

## Phase 1 — Investigate

Before writing anything, gather the facts:

- Read the error message, stack trace, or description in `$ARGUMENTS` carefully
- Use `codegraph_context` or `Explore` agent to locate relevant files, symbols, and call sites
- Check git status / recent changes that could be the cause
- Reproduce the failure if possible (run tests, check logs, inspect state)
- Identify the **root cause**, not just the symptom

Do NOT skip investigation even if the fix seems obvious. Silent assumptions cause wrong fixes.

---

## Phase 2 — Report

Present a clear, concise diagnosis:

```
## Issue
[One-sentence description of what is broken and where]

## Root Cause
[Why it's broken — the underlying reason, not just the symptom]

## Evidence
- `file:line` — [what you found there]
- `file:line` — [what you found there]
```

Keep it tight. Use file:line references so the user can jump to the code.

---

## Phase 3 — Suggest Fix

Propose your fix **before touching any code**:

```
## Proposed Fix
[What you will change and why — one paragraph]

### Changes
- `file:line` — [what changes]
- `file:line` — [what changes]

### Why this works
[Brief explanation of how this addresses the root cause]

### Trade-offs / risks
[Any side effects, assumptions, or limitations]
```

If there are multiple valid approaches, show them as **Option A / Option B** with a recommendation.

Then use `AskUserQuestion` to ask: **"Proceed with this fix?"** — do NOT touch any files until the user confirms.

---

## Phase 4 — Fix

After confirmation:

1. Apply every change described in Phase 3 — no more, no less
2. Run tests or linting if applicable and report results
3. Explain each change as you make it (what was removed/added/modified and why)
4. Confirm the fix resolves the reported issue

---

## Phase 5 — Optional Follow-ups (only if relevant)

After the fix is applied, surface anything worth knowing:

- Related issues in nearby code that could cause the same class of bug
- Missing tests that would have caught this
- Tech debt or design smell that contributed to the bug
- Any config, docs, or dependency that should be updated

Keep this section short. If there's nothing worth flagging, skip it entirely.

---

## Phase 6 — Wrap Up

Once the fix is applied, verified, and any follow-ups are surfaced:

1. Confirm the fix resolves the reported issue and summarize what changed
2. Do **not** create the PR yourself — no `gh pr create`, no push beyond what the fix required
3. Prompt the user to run `/pr` themselves:
   > "Fix applied and verified. Run `/pr` when you're ready to open the pull request — it handles branch push, PR templating, and readiness checks."

---

## Rules

- **Never edit files before getting confirmation in Phase 3.**
- Always include file:line references — no vague "somewhere in the auth module."
- If `$ARGUMENTS` is empty, ask the user what to fix before starting Phase 0.
- If the issue is ambiguous (could be multiple root causes), say so and ask one clarifying question before investigating.
- For destructive changes (deleting files, dropping tables, force-pushing), flag explicitly and require explicit confirmation.
- **Never create or push a PR from this workflow** — PR creation is `/pr`'s job.
