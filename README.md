# claude-skills

Custom slash commands for [Claude Code](https://claude.ai/code). Drop these into
`~/.claude/commands/` (global) or `.claude/commands/` (per-project) and invoke with `/<name>`.

## Install

```bash
git clone git@github.com:quniv/claude-skills.git
ln -s "$(pwd)/claude-skills/commands/"*.md ~/.claude/commands/
```

Or symlink individual files if you only want some of them.

## Skills

| Command | Purpose |
|---|---|
| `/commit` | Stages changes, writes a commit message, confirms the branch, and optionally pushes. |
| `/feat` | Feature-branch orchestrator — sets up a clean worktree, then drives implementation via the task orchestrator. |
| `/fix` | Focused debugging workflow — branches, investigates, proposes a fix, and applies it after confirmation. |
| `/hey` | Read-only project pulse check — git status, open PRs/issues, worktrees — with a suggested next step if something needs attention. |
| `/pr` | End-to-end PR workflow — creates the PR, then loops through conflicts, failing checks, and review comments until it's mergeable. |

## Notes

- Each skill is a self-contained Markdown file — read it before using it, they're not black boxes.
- Several skills (`/pr`, `/fix`, `/feat`) assume the `gh` CLI is authenticated and lean on `AskUserQuestion`-style confirmation before anything destructive (pushes, commits, conflict resolution).
- These were written for a specific workflow (zsh, git, GitHub) — adjust freely for yours.
