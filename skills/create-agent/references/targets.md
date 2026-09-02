# Agent targets: paths and format differences

## Discovery paths

| Tool | Project scope | User scope |
|---|---|---|
| Claude Code | `<repo>/.claude/agents/<name>.md` | `~/.claude/agents/<name>.md` |
| Codex CLI | `<repo>/.codex/agents/<name>.toml` | `$CODEX_HOME/agents/<name>.toml`, default `~/.codex/agents/` |

Codex resolves the project layer to `.codex/` and the user layer to
`$CODEX_HOME`, scanning the `agents/` subfolder of each.

## Claude Code — Markdown with frontmatter

```markdown
---
name: tf-reviewer
description: Reviews Terraform plans for destructive changes before apply. Delegate when a plan needs a safety check.
tools: Read, Grep, Bash
model: sonnet
---

You review Terraform changes before they reach a shared environment.
...
```

- `name` and `description` are required; `name` must equal the filename stem.
- `tools` is a comma-separated allowlist. **Omit it to inherit every tool** —
  an allowlist that is too tight produces an agent that cannot do its job.
- `model` accepts `sonnet`, `opus`, `haiku`, or `inherit`. Omit to inherit.
- Everything after the frontmatter is the agent's system prompt.

## Codex — TOML

```toml
name = "tf-reviewer"
description = "Reviews Terraform plans for destructive changes before apply."
model_reasoning_effort = "high"
developer_instructions = '''
You review Terraform changes before they reach a shared environment.
...
'''
```

- `name`, `description`, and `nickname_candidates` are role fields; any
  `config.toml` key may also appear at the top level, including
  `developer_instructions`, `model`, and `model_reasoning_effort`.
- **A file without `developer_instructions` produces a startup warning and an
  empty role.** It is the field that carries the entire system prompt.
- `agent_tool.py` emits a literal `'''` string so Markdown backslashes and
  backticks survive verbatim, and falls back to an escaped `"""` string only if
  the body itself contains `'''`.

## Why full copies, not an adapter

The tempting design is one canonical `INSTRUCTIONS.md` with thin per-tool files
that say "read that file first." It does not work:

- A Claude Code subagent's system prompt is the file body. There is no
  indirection step, so the agent boots with a one-line prompt and never loads
  the role.
- Codex would follow such an instruction only if the file were readable at run
  time from the agent's working directory — which is not guaranteed for a user-
  scope agent, or after the repo is cloned elsewhere.

Render the whole role into every target. Sharing happens at authoring time,
through one `--body-file`, not at run time through a pointer.

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
