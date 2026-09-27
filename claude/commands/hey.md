# Project Pulse — /hey

You are a read-only status agent. Your job: give the user a fast, honest snapshot of where
this project stands right now — no changes, no branches, no commits. Just look, think, report.

Arguments (optional): $ARGUMENTS — if provided, narrow the check to a specific area (e.g.
"issues", "PRs", "git") instead of the full sweep.

---

## Phase 0 — Check for pull

- Run `git fetch` and `git status --short --branch` to see if the current branch is behind
  its upstream.
- If behind: ask the user via `AskUserQuestion` whether to pull latest before investigating.
  Options: "Pull first" (recommended if behind) / "Investigate as-is".
- If the user chooses to pull, run `git pull` (fast-forward only — if it's not a clean
  fast-forward, abort the pull and report why, don't force or rebase), then continue to
  Phase 1 against the fresh state.
- If not behind, or there's no upstream to compare against, skip this step silently — don't ask.

---

## Phase 1 — Gather

Run these in parallel where possible. Don't ask permission — everything here is read-only.

**Git state:**
- `git status --short --branch` — current branch, staged/unstaged/untracked files
- `git stash list` — anything stashed and forgotten
- `git branch -vv` — local branches and their upstream tracking state (ahead/behind)
- `git worktree list` — any other worktrees checked out
- `git log --oneline <base>..HEAD -20` — commits on this branch not yet on the base (skip if on base branch)

**GitHub state** (skip gracefully if `gh` isn't authenticated or repo has no remote):
- `gh issue list --state open --limit 30` — open issues
- `gh pr list --state open --json number,title,author,isDraft,reviewDecision,statusCheckRollup,headRefName` — all open PRs
- If any open PR's `headRefName` matches the current branch, treat it as "your PR in flight" and note its check/review status specifically

**Memory check:**
- Skim this project's memory index for any pending/in-flight items (e.g. a noted "pending" PR, a partially-done migration) that might explain current state — but verify against live `gh`/`git` output before repeating anything as current fact, since memory can go stale.

---

## Phase 2 — Synthesize and Report

Don't dump raw command output. Turn it into a short, scannable report:

```
## Where things stand

**Branch**: <branch> (<ahead/behind base>, <clean|N uncommitted changes>)
**Worktrees**: <none other | list>
**Stashes**: <none | N stashes, oldest from <date>>

**Open PRs** (<N>):
- #<n> <title> — <draft|ready>, checks: <passing|failing|pending>, review: <status>
  [flag if this is the current branch's PR]

**Open issues** (<N>):
- #<n> <title> <if there's an obvious link to current branch/PR, say so>

**Notes from memory**: <only if genuinely still relevant and verified — otherwise omit>
```

Keep it tight — this is a status check, not a report. Omit empty sections entirely rather than
writing "none found" for everything.

After the report, add 1-3 sentences of actual synthesis — connect the dots a human would want
pointed out: "PR #99 is green and unreviewed — probably just needs a merge", "you have uncommitted
changes on main from 3 days ago that never got a branch", "issue #12 looks like it's already fixed
by your last commit but is still open".

---

## Phase 3 — Suggest or Stand Down

- If you found something actionable (failing check, stale uncommitted work, an open PR ready to
  merge, an issue that looks resolved, a stash that's been sitting for a while) — suggest **one**
  specific next step. Don't list five hypothetical options; pick the most useful one and say why.
- If nothing stands out — say so directly ("Nothing needs attention — working tree is clean, no
  open PRs or issues.") and stop there. Do not create tasks, open branches, or start any work.
  Wait for the user's next instruction.

---

## Rules

- Never modify git state, create branches, or touch files in this command — it is observation only.
- If `gh` isn't authenticated, note it once and continue with the git-only portions rather than failing.
- Don't repeat a memory fact as current truth without cross-checking it against live output first.
