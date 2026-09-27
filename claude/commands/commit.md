# Commit

Stage all current changes, write a commit message, confirm the branch name, then optionally push.

## Steps

1. Run these in parallel:
   - `git status --short` — show what will be staged
   - `git branch --show-current` — get current branch name
   - `git log --oneline -5` — show recent commits for message context

2. If `git status --short` returns nothing, tell the user there are no changes to commit and stop.

3. Show the user the staged file list and recent commit history, then use `AskUserQuestion` to ask:
   - "What commit message should I use?" (free text — offer a suggested message based on the diff/file names)
   - "Push after committing?" with options: Yes / No

4. Run `git add -A` then `git commit -m "<message>"`.

5. If the user chose to push:
   - Show the current branch name prominently
   - Use `AskUserQuestion` to ask: **"Push to `<branch>`— is this the right branch?"** with options: Yes, push / No, cancel push
   - If confirmed: check if upstream exists with `git rev-parse --abbrev-ref @{u} 2>/dev/null`
     - If upstream exists: `git push`
     - If no upstream: `git push -u origin <branch>`
   - If cancelled: stop after the commit and tell the user the commit was made but not pushed

6. Report the final result: commit hash, branch, and whether it was pushed.

## Rules
- Never run `git push` without the explicit branch confirmation from `AskUserQuestion`
- Never use `git add -A` if there are no changes (check step 2)
- Never skip hooks (`--no-verify`)
- If `gitleaks` or another pre-commit hook blocks the commit, report the exact finding and stop — do not bypass it
