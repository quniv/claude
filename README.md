# claude-skills

Custom slash commands, skills, and tooling for [Claude Code](https://claude.ai/code).

- **Commands** (`commands/`) are invoked explicitly as `/<name>`.
- **Skills** (`skills/`) are invoked by name *or* picked up automatically when the
  model decides their description matches the task.
- **Global instructions** (`global/CLAUDE.md`) apply to every project.
- **Terminal setup** (`terminal/`) is the Ghostty + zsh + Starship environment
  this all runs in — see [`terminal/README.md`](terminal/README.md).

Each lives in a different place under `~/.claude/` — see Install.

## Install

```bash
git clone git@github.com:quniv/claude-skills.git
mkdir -p ~/.claude/commands ~/.claude/skills

# Commands -> /<name>
ln -s "$(pwd)/claude-skills/commands/"*.md ~/.claude/commands/

# Skills -> one directory each, symlink the directory, not the SKILL.md,
# so bundled templates and agent manifests come along.
ln -s "$(pwd)/claude-skills/skills/"*/ ~/.claude/skills/

# Global instructions — back up any existing file first, `ln -s` refuses to
# clobber it. Add -f once you are sure you want to replace it.
ln -s "$(pwd)/claude-skills/global/CLAUDE.md" ~/.claude/CLAUDE.md
```

`ln -s` fails rather than overwrites when the destination already exists, so a
partial install is safe to re-run once you have moved the conflicting file out
of the way. Symlink individual entries if you only want some of them.

### Status line

`statusline/statusline.sh` is a robbyrussell-style status line — shows cwd, git
branch/dirty state, model + reasoning effort, context window usage, 5-hour rate
limit usage, and a session context summary.

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

### Terminal setup

`terminal/` holds the shell and terminal environment itself — Ghostty, zsh
(oh-my-zsh), and a Starship prompt on a shared cyberpunk-neon palette. These
land outside `~/.claude/`, and they have prerequisites; read
[`terminal/README.md`](terminal/README.md) before linking them.

```bash
mkdir -p ~/.config/ghostty

ln -s "$(pwd)/claude-skills/terminal/zshrc"          ~/.zshrc
ln -s "$(pwd)/claude-skills/terminal/zprofile"       ~/.zprofile
ln -s "$(pwd)/claude-skills/terminal/starship.toml"  ~/.config/starship.toml
ln -s "$(pwd)/claude-skills/terminal/ghostty/config" ~/.config/ghostty/config
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
when the task matches — no slash command required.

| Skill | Purpose |
|---|---|
| `create-skill` | Builds a skill and installs it into every coding agent's own standard directory. |
| `create-agent` | Builds a subagent and renders it natively for every coding agent. |
| `gitmain` | Returns the repositories under the current directory to `main`, asking what to do with uncommitted work in each one before switching. |
| `savework` | Writes a short session recap to `.history/` in the project root, so the next session gets oriented without re-deriving context. Bundles the `.history/CLAUDE.md` template it installs. |

`savework` is most useful paired with the `global/CLAUDE.md` rule that tells
Claude to run it unprompted after something lands.

### create-skill / create-agent

These two are cross-agent: they generate skills and subagents for **any** coding
agent, writing into the directory each tool actually scans rather than a bespoke
one. Both take a single authored body and render a complete, self-contained
definition per target — no symlinks, no adapter files pointing at a canonical
copy that a moved or cloned repo would break.

| | Claude Code | Codex CLI |
|---|---|---|
| Skill, project | `.claude/skills/<name>/` | `.codex/skills/<name>/` |
| Skill, user | `~/.claude/skills/<name>/` | `$CODEX_HOME/skills/<name>/` |
| Agent, project | `.claude/agents/<name>.md` | `.codex/agents/<name>.toml` |
| Agent, user | `~/.claude/agents/<name>.md` | `$CODEX_HOME/agents/<name>.toml` |

Each bundles one stdlib-only Python helper — no `pip`, no `uv`, no install step,
so any agent on any machine can run it:

```bash
# Where would this land?
python3 skills/create-skill/scripts/skill_tool.py paths --name my-skill

# Write it everywhere at once
python3 skills/create-skill/scripts/skill_tool.py scaffold \
  --name my-skill --description '...' --body-file body.md --scope project

# Check it
python3 skills/create-skill/scripts/skill_tool.py validate --name my-skill
```

`agent_tool.py` in `create-agent` takes the same three subcommands. Both refuse
to overwrite without `--force`, refuse to write through a symlink even with it,
and reject names that are not lowercase hyphen-case.

To support another coding agent, add its paths to `scripts/agent_targets.py` and
its format to the renderer — the workflow around it does not change.

## Global instructions

`global/CLAUDE.md` is the always-on preamble for every project: prefer diagrams
over prose, keep writing plain, and recap finished work to `.history/`. Symlink
it to `~/.claude/CLAUDE.md`. Per-project `CLAUDE.md` files stack on top of it
rather than replacing it.

## Notes

- Each command and skill is plain Markdown — read it before using it, they're not black boxes.
- Several skills (`/pr`, `/fix`, `/feat`) assume the `gh` CLI is authenticated and lean on `AskUserQuestion`-style confirmation before anything destructive (pushes, commits, conflict resolution).
- These were written for a specific workflow (zsh, git, GitHub) — adjust freely for yours.
