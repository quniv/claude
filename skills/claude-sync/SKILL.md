---
name: claude-sync
description: Sync personal Claude Code config (global CLAUDE.md, commands, statusline, own skills) between ~/.claude and the public quniv/claude repo via symlinks. Use to publish local config changes, add a skill or file to the sync, set up config on a new machine, or pull updates from another machine. Not for project-level CLAUDE.md files, settings.json, or authoring a skill's content (use create-skill).
---

# Claude Sync

`~/.claude` entries are symlinks into a clone of `github.com/quniv/claude`. Editing the config edits the clone, so syncing is git. `claude/links.tsv` maps repo paths to paths under `$HOME`. `scripts/sync.sh` resolves the clone from its own location.

```text
~/.claude/CLAUDE.md       -> <clone>/claude/CLAUDE.md
~/.claude/commands        -> <clone>/claude/commands
~/.claude/skills/<name>   -> <clone>/skills/<name>
```

## Invariants

- **Keep the linked clone on `main`.** `~/.claude` follows its working tree; checking out another branch swaps the live config. Do other work in a git worktree. `sync.sh link` and `adopt` refuse off `main`.
- **The repo is public.** Never sync `settings*.json`, `.credentials.json`, `history.jsonl`, `projects/` (memory), `sessions/`, `plugins/`, `skills/synced/` (claude.ai-managed), or skills written by others.
- **Never push `main`.** Commit on local `main`, push `HEAD` to a `sync/*` branch, open a PR. The user merges it with a merge commit, so local `main` fast-forwards afterwards.
- Never delete local files. `link` moves an identical original to `~/.claude/backups/claude-sync-<ts>/`; it skips anything that differs.

## Commands

```bash
S=~/.claude/skills/claude-sync/scripts/sync.sh   # or <clone>/skills/claude-sync/scripts/sync.sh
$S status                  # ok | missing | same | differs | wrong-link | repo-missing per entry
$S link [--dry-run]        # create missing links
$S adopt <path> <repo>     # move a local file/dir into the repo and link it
$S scan                    # gitleaks over staged changes
```

## Publish local changes

1. `cd "$(dirname "$(readlink -f ~/.claude/CLAUDE.md)")/.."`. Confirm branch `main`, then `git fetch` and `git pull --ff-only`.
2. `git status` and `git diff`. Read the whole diff for private content: names, emails, hostnames, internal URLs, client or employer details. Stop and ask if any appear.
3. Stage only the intended paths, then `$S scan`. Never publish on a failed or skipped scan.
4. Commit on `main` with a short imperative message.
5. `b=sync/$(hostname -s)-$(date +%Y%m%d-%H%M)`, then `git push origin HEAD:refs/heads/$b` and `gh pr create --base main --head $b --fill`.
6. Report the PR URL. After the user merges, `git pull --ff-only`. If that fails (squash or rebase merge), stop and ask; do not reset.

## Add something to the sync

Only for the user's own work. Run `$S adopt ~/.claude/skills/<name> skills/<name>` (or `claude/<file>` for non-skill files). It copies into the repo, appends `links.tsv`, adds the `.agents/skills/<name>` link for skills, and replaces the original with a symlink. Then publish.

## Set up a new machine

1. Ask where to clone. `git clone https://github.com/quniv/claude <dir>`, stay on `main`.
2. `<dir>/skills/claude-sync/scripts/sync.sh link --dry-run`; show the plan.
3. For each `differs`, show `diff -r` and ask which side wins before touching it. Then run `link`.

## Pull updates

In the clone: `git pull --ff-only`, then `$S link` to pick up new manifest entries. `$S status` should show only `ok`.
