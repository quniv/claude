# claude-skills

Custom slash commands and tooling for [Claude Code](https://claude.ai/code). Drop the
commands into `~/.claude/commands/` (global) or `.claude/commands/` (per-project) and
invoke with `/<name>`.

## Install

```bash
git clone git@github.com:quniv/claude-skills.git
ln -s "$(pwd)/claude-skills/commands/"*.md ~/.claude/commands/
```

Or symlink individual files if you only want some of them.

### Status line

`statusline/statusline.sh` is a robbyrussell-style status line — shows cwd, git
branch/dirty state, context window usage, 5-hour rate limit usage, and a
session context summary.

```bash
ln -s "$(pwd)/claude-skills/statusline/statusline.sh" ~/.claude/statusline.sh
```

Then point `statusLine` in `~/.claude/settings.json` at it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

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
