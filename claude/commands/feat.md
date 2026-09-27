# Feature Branch Workflow

You are a feature development orchestrator. Safely set up a clean feature worktree, then drive implementation using the Task Orchestrator.

**Request:** $ARGUMENTS

---

## Phase 1 — Pre-flight Check

Run these in parallel:
- `git status --porcelain`
- `git branch --show-current`
- `git rev-parse --show-toplevel`

---

## Phase 2 — Create Worktree

Always create a worktree — never work directly in the main repo checkout.

**Step 1 — Derive branch name from `$ARGUMENTS`:**
- Slug: lowercase, max 4 significant words, hyphens only
- Append today's date as DDMMYYYY — get from `date +%d%m%Y`
- Prefix with `feat/`
- Example: "add rate limiting to API" → `feat/add-rate-limiting-08062026`

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
- Example: repo at `/home/user/home-argocd`, branch `feat/add-auth-08062026` → path `/home/user/feat-add-auth-08062026`

**Step 5 — Create the worktree from main:**
```
git worktree add <worktree-path> -b <branch-name> <main-branch>
```

**Step 6 — Inform the user:**
> "Worktree created at `<path>` on branch `<branch>`. Your current work in the main repo is untouched.
> Open a terminal in that directory to continue there. Proceeding with implementation plan..."

**Step 7 — Continue to Phase 3**, running all implementation work with context set to the worktree path.

---

## Phase 3 — Implement

Now orchestrate the implementation as the Task Orchestrator does.

### Context Checklist (run before breakdown)

- [ ] What project is this? (cwd, git remote, stack)
- [ ] Any active CLAUDE.md conventions in scope?
- [ ] Does this touch shared/prod infrastructure? (flag before executing)

### Step A — Clarify (only if needed)

Scan the request for blockers:
- Missing scope (which project? which service? which environment?)
- Missing constraints (language/framework? prod vs dev? destructive ok?)
- Genuinely ambiguous intent (two different valid interpretations)

**Do NOT ask** about things inferable from: current directory, git state, project CLAUDE.md files, stack already in use.

If ambiguous: use `AskUserQuestion` with **at most 3 focused questions**.
If clear: skip to Step B.

### Step B — Break Down

Decompose into atomic subtasks. Show a numbered plan:

```
1. [What] — [Agent type] — depends on: none
2. [What] — [Agent type] — depends on: 1
3. [What] — [Agent type] — depends on: none
```

For each subtask include:
- **What**: the specific action (concrete, not vague)
- **Agent**: which specialist handles it (see roster below)
- **Depends on**: task numbers that must finish first (empty = runs immediately)
- **Done when**: clear success condition

For non-trivial plans (>3 subtasks or risky/destructive steps), confirm with the user before executing.

### Step C — Execute

1. Launch all dependency-free tasks **in parallel** (multiple Agent tool calls in one message)
2. As each finishes, unblock dependents immediately
3. If a subtask fails or surprises — adapt the plan, don't stop
4. Synthesize all results into a clear final summary

### Agent Roster

| Agent type | Use for |
|---|---|
| `Explore` | Fast read-only search: find files, grep symbols, locate patterns |
| `Plan` | Architecture decisions, implementation strategy, trade-off analysis |
| `general-purpose` | Multi-step research, complex analysis, writing, cross-file tasks |
| `cicd-engineer` | CI/CD pipelines: GitHub Actions, Azure DevOps, GitLab CI, Jenkins |
| `claude` | Catch-all — tasks that don't fit a specialist |

---

## Phase 4 — Wrap Up

Once implementation is complete and verified (build passes, tests green, changes match the plan):

1. Summarize what changed — files touched, what was added/removed/modified, and why
2. Do **not** create the PR yourself — no `gh pr create`, no push beyond what implementation required
3. Prompt the user to run `/pr` themselves:
   > "Implementation done and verified. Run `/pr` when you're ready to open the pull request — it handles branch push, PR templating, and readiness checks."

---

## Rules

- **Never create or push a PR from this workflow** — PR creation is `/pr`'s job. When the task is finished, hand off by asking the user to run `/pr`.
