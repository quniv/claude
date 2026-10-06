# claude

Custom slash commands, skills, and tooling for [Claude Code](https://claude.ai/code).

- **Commands** (`claude/commands/`) are invoked explicitly as `/<name>`.
- **Skills** (`skills/`) are invoked by name *or* picked up automatically when the
  model decides their description matches the task.
- **Global instructions** (`claude/CLAUDE.md`) apply to every project.
- **Status line** (`claude/statusline-command.sh`) for the Claude Code footer.
- **Terminal setup** (`terminal/`) is the Ghostty + zsh + Starship environment
  this all runs in — see [`terminal/README.md`](terminal/README.md).
- **GNOME Shell setup** (`gnome/`) installs the desktop extensions and their
  settings. See [`gnome/README.md`](gnome/README.md).

```text
repo                            ~/.claude (symlinks, per claude/links.tsv)
├── claude/CLAUDE.md        ──▶ CLAUDE.md
├── claude/commands/        ──▶ commands/
├── claude/statusline-command.sh ──▶ statusline-command.sh
└── skills/<name>/          ──▶ skills/<name>/
```

## Install

```bash
git clone https://github.com/quniv/claude ~/claude
~/claude/skills/claude-sync/scripts/sync.sh link --dry-run   # preview
~/claude/skills/claude-sync/scripts/sync.sh link
~/claude/skills/claude-sync/scripts/sync.sh status           # every line should be "ok"
```

`link` never overwrites. An identical existing file is moved to
`~/.claude/backups/claude-sync-<timestamp>/`; anything that differs is skipped
and reported, so resolve it by hand and rerun. Keep the clone on `main`:
`~/.claude` follows its working tree.

Requirements: `git`, `jq` (status line), `gh` (PR commands), `gitleaks`
(`sync.sh scan`).

### Status line

Point `statusLine` in `~/.claude/settings.json` at the linked script:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

It shows cwd, git branch/dirty state, model + reasoning effort, AWS profile,
context window usage, 5-hour rate limit usage, CPU/RAM/disk usage, and a session
context summary. The system usage segment needs Linux `/proc`. Each value turns
yellow at 75% and red at 90%.

### Terminal setup

`terminal/` holds the shell and terminal environment itself — Ghostty, zsh
(oh-my-zsh), and a Starship prompt on a shared cyberpunk-neon palette. These
land outside `~/.claude/` and are not managed by `sync.sh`; they have
prerequisites, so read [`terminal/README.md`](terminal/README.md) before linking them.

```bash
mkdir -p ~/.config/ghostty

ln -s ~/claude/terminal/zshrc          ~/.zshrc
ln -s ~/claude/terminal/zprofile       ~/.zprofile
ln -s ~/claude/terminal/starship.toml  ~/.config/starship.toml
ln -s ~/claude/terminal/ghostty/config ~/.config/ghostty/config
```

### GNOME Shell setup

`gnome/` installs the GNOME Shell extensions and loads their settings. Read
[`gnome/README.md`](gnome/README.md) for the list and the requirements.

```bash
~/claude/gnome/install.sh   # then log out and back in
```

## Commands

| Command | Purpose |
|---|---|
| `/commit` | Stages changes, writes a commit message, confirms the branch, and optionally pushes. |
| `/feat` | Feature-branch orchestrator — sets up a clean worktree, then drives implementation via the task orchestrator. |
| `/fix` | Focused debugging workflow — branches, investigates, proposes a fix, and applies it after confirmation. |
| `/hey` | Read-only project pulse check — git status, open PRs/issues, worktrees — with a suggested next step if something needs attention. |
| `/pr` | End-to-end PR workflow — creates the PR, then loops through conflicts, failing checks, and review comments until it's mergeable. |

## Skills

Skills carry their own trigger description, so Claude can invoke them on its own
when the task matches — no slash command required. `.agents/skills/` links each
one for Codex as well.

| Skill | Purpose |
|---|---|
| `claude-sync` | Links `~/.claude` to this repo, adopts new local files into it, and publishes changes through `sync/*` branches and PRs. |
| `create-skill` | Creates or updates a workspace skill under `skills/<name>` and exposes it to Codex through `.agents/skills`. |
| `create-agent` | Creates or updates a workspace agent as `agents/<name>/INSTRUCTIONS.md` plus a Codex `.codex/agents/<name>.toml` adapter, with linked skills. |
| `gitmain` | Returns the repositories under the current directory to `main`, asking what to do with uncommitted work in each one before switching. |
| `pr` | Commits all current changes onto a new branch from `main`/`develop` and pushes it after confirmation. |
| `push` | Commits every current change and pushes the current branch, no questions asked. |
| `savework` | Writes a short session recap to `.history/` in the project root, so the next session gets oriented without re-deriving context. |
| `terraform` | House rules for Terraform code: one file per AWS service, naming, safe renames and imports, and plan verification. |

`savework` is most useful paired with the `claude/CLAUDE.md` rule that tells
Claude to run it unprompted after something lands.

## Global instructions

`claude/CLAUDE.md` is the always-on preamble for every project: read-only access
to every server and cloud, confirm before deleting anything, flag security, cost
and optimization findings, prefer diagrams over prose, short code comments and PR
descriptions, and read and write session recaps in `.history/`.
Per-project `CLAUDE.md` files stack on top of it rather than replacing it.

## Notes

- Each command and skill is plain Markdown — read it before using it, they're not black boxes.
- This repo is public. Never add `settings*.json`, credentials, history, memory or other people's skills; `sync.sh scan` runs gitleaks before publishing.
- Several commands and skills (`/pr`, `/fix`, `/feat`, `pr`, `push`) assume the `gh` CLI is authenticated and confirm before anything destructive.
- These were written for a specific workflow (zsh, git, GitHub) — adjust freely for yours.
