---
name: push
description: Stage every current repository change, create one concise imperative commit, and push the current branch to its remote without asking follow-up questions. Use when the user says "push", "commit and push", "ship these changes", or explicitly invokes $push.
---

# Push Changes

Complete the repository handoff autonomously. Do not ask for confirmation or a commit message.

1. Confirm the working directory belongs to a Git repository. Read repository instructions and inspect `git status --short`, the current branch, configured remotes, `git diff`, and `git diff --cached`.
2. Stop and report the blocker without changing history when detached HEAD is active, no remote exists, merge conflicts exist, or the diff contains an apparent secret, credential, private key, state file, or generated plan.
3. Run the repository's documented fast validation when it is discoverable and proportionate. Do not invent broad or destructive cleanup. If validation fails, stop and report it.
4. Stage everything with `git add -A`, including deletions and untracked files requested by the user's current workspace state.
5. Run the repository's configured secret scan against staged changes when available. Never bypass a failed scan.
6. Derive a short imperative commit subject from the complete staged diff. Keep the commit focused on the actual outcome. Commit normally; never bypass hooks.
7. Push the current branch. If it has no upstream, use `git push -u origin <current-branch>`. Otherwise use `git push`. Never force-push.
8. Report the commit hash, subject, branch, remote, validation results, and push result. If there was nothing to commit, report that and push any existing unpushed commits.

Treat invocation of this skill as explicit authorization to stage, commit, and push all current changes. Do not expand that authorization to force pushes, history rewrites, deleting branches, changing remotes, or bypassing repository safeguards.
