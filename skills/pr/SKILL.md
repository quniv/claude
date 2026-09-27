---
name: pr
description: Stage and commit all current repository changes, create a new branch from the repository's main or develop branch, and push it after explicit confirmation. Use when the user asks to prepare, branch, and push all current work automatically.
---

# Prepare And Push Current Changes

Complete the repository workflow automatically except for the final push, which requires explicit user confirmation immediately before it runs.

## Workflow

1. Inspect the worktree, current branch, configured remotes, and available `main` and `develop` branches. Preserve every current tracked and untracked change.
2. Choose the base branch from repository evidence. Prefer the repository's configured default branch; otherwise use `develop` when it exists, then `main`. If neither exists locally or on the remote, stop and explain the blocker.
3. Fetch the selected base branch when a remote is configured and fetching is permitted. Do not merge, rebase, reset, clean, stash, or discard the user's changes.
4. Create and check out a new branch from the selected base while keeping all current changes. Derive a concise, valid branch name from the changes, avoiding collisions by adding a short numeric suffix when needed.
5. Stage all current changes with `git add -A`.
6. Review the staged diff and create one concise imperative commit that accurately describes the complete change set. If there is nothing to commit, stop and report that no commit was created.
7. Show the user the new branch name, base branch, commit summary, and destination remote. Ask for explicit confirmation to push.
8. Only after confirmation, push the new branch and set its upstream. Do not create a pull request unless the user separately requests one.

## Safety

- Treat staging, committing, branch creation, and checkout as authorized by invocation of this skill.
- Never push without confirmation in the current conversation, even if the user initially asked for the entire workflow to be automatic.
- Stop on conflicts, failed checks, missing identity, hooks, authentication errors, or ambiguous repository state. Report the exact issue without bypassing safeguards.
- Do not amend existing commits or force-push.
