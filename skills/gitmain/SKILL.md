---
name: gitmain
description: Switch one or more repositories to their main branch while protecting uncommitted work. Use when the user asks to return repositories in the current directory tree to main or their primary branch.
---

# Switch Repositories To Main

Find the relevant Git repositories and safely switch each selected repository to its primary branch.

## Repository Selection

1. Determine whether the current working directory is itself a Git repository and discover distinct repositories below it without traversing into `.git` directories.
2. If exactly one repository is found, select it automatically.
3. If multiple repositories are found, list their concise relative paths and ask the user to choose one, several, or all. Do not modify any repository until they answer.
4. If no repository is found, stop and report that clearly.

## Branch Selection

For each selected repository, use local or remote `main`. If `main` does not exist, use the configured remote default branch only when it is clearly the repository's primary branch; otherwise report that repository as blocked rather than guessing or creating a branch.

## Protect Current Work

Inspect tracked, staged, unstaged, and untracked changes before checkout. If a selected repository has any changes, show a concise status summary and ask what action the user wants before switching it. Offer only applicable choices such as commit, stash including untracked files, discard, skip, or cancel. Treat discard as destructive and require explicit confirmation immediately before performing it.

Do not infer an action, combine repositories into one decision, or switch a dirty repository until the user gives instructions for that repository. Carry out the chosen action, verify the worktree state, then continue.

## Checkout

- Fetch only when needed to resolve or update the target branch and a remote is configured.
- If the target branch exists locally, check it out. Otherwise create a tracking branch from the matching remote branch.
- Do not reset, clean, force checkout, delete branches, or rewrite history unless the user explicitly chose the corresponding destructive action.
- Process all selected repositories and report each final branch, skipped repository, or blocker.
