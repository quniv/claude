# Skill targets: paths and format differences

Read this before writing to any target. Every path below is what the tool
actually scans — nothing here is a convention this repository invented.

## Discovery paths

| Tool | Project scope | User scope |
|---|---|---|
| Claude Code | `<repo>/.claude/skills/<name>/` | `~/.claude/skills/<name>/` |
| Codex CLI | `<repo>/.codex/skills/<name>/` | `$CODEX_HOME/skills/<name>/`, default `~/.codex/skills/<name>/` |

Codex resolves skill roots in this precedence order: `.codex/skills` from the
project config layer (repo scope, highest), plugin roots, extra configured user
roots, then `.agents/skills` found by walking up from the working directory
(lowest). `.agents/skills/` therefore *works*, but it is the weakest root and is
shadowed by everything else — prefer `.codex/skills/`.

`$CODEX_HOME` is honoured when set; `scripts/agent_targets.py` reads it.

## Shared shape

Both tools read the same directory layout, which is why one authored body can be
rendered into both:

```text
<name>/
|-- SKILL.md        required: YAML frontmatter + Markdown body
|-- scripts/        optional: executable helpers
|-- references/     optional: detail loaded on demand
`-- assets/         optional: files copied into produced output
```

`SKILL.md` frontmatter requires `name` and `description` in both tools. The
directory name must equal `name`.

## Where they differ

| | Claude Code | Codex CLI |
|---|---|---|
| Extra frontmatter | `allowed-tools` | `allowed-tools`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `context`, `agent`, `model` |
| Picker metadata | none — no such file | `agents/openai.yaml` with `interface.display_name`, `.short_description`, `.default_prompt` |
| Invocation | `/<name>`, or automatic on description match | `$<name>`, or automatic on description match |

`agents/openai.yaml` is inert in Claude Code, so writing it into a Claude target
is harmless but pointless; `skill_tool.py` only emits it for Codex targets.

Frontmatter keys one tool does not recognise are ignored rather than fatal, but
do not scatter them — a reader cannot tell an intentional key from a typo.

## Why complete copies, not symlinks

A single canonical copy with symlinks or pointer files into the other targets
fails in three ordinary situations:

- the repository moves, and every absolute symlink dangles;
- the skill is committed and cloned elsewhere, where the symlink target does not
  exist;
- the user installs one tool but not the other.

Each target is cheap — a skill is text. Write a real one per target and let each
tool own its copy. When the user genuinely wants one source of truth, that
belongs in a dotfiles repository they symlink deliberately, not in output this
skill generates behind their back.

## `agent_targets.py` is duplicated on purpose

Each skill carries its own byte-identical copy of `scripts/agent_targets.py`.
That is deliberate: a skill must keep working when it is the only one installed,
and neither tool resolves imports across skill directories.

Nothing keeps the copies in sync automatically. **When you change one, change
both**, and confirm with:

```bash
diff skills/create-skill/scripts/agent_targets.py \
     skills/create-agent/scripts/agent_targets.py
```

Adding support for another coding agent means editing this file in both places.
