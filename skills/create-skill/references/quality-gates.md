# Quality gates

Apply before writing, and again before reporting completion.

## The description carries the whole trigger

Every tool matches on frontmatter before it loads the body. A description that
only says what the skill *is* will never fire at the right moment.

Write it as: what it does, then **when to use it**, with concrete cues in the
user's own vocabulary — including the literal invocation (`/name`, `$name`) and
the phrases a user would actually type.

- Weak: `Creates documentation for a project.`
- Strong: `Generate reference docs from source comments into docs/api/. Use when
  the user asks to document an API, refresh generated docs, or says /gen-docs.`

State non-triggers in the description too when a near-miss skill exists.

## Structure

- Directory name equals frontmatter `name`. Lowercase hyphen-case, 1–64 chars.
- `SKILL.md` stays short enough to read in full; push detail into `references/`.
- Every reference is one level from `SKILL.md`, and the body says exactly when to
  read each one. A reference nothing points at is dead weight.
- No empty resource directories. No README, changelog, install guide, or version
  history inside a skill — that is repository documentation, not skill content.

## Body

- Imperative, second person, addressed to the agent that will run it.
- Concrete over abstract: real commands, real paths, real file names.
- State the boundaries explicitly, including what the skill must not do.
- Name the approval points, and say what happens on each failure mode.
- No persona inflation, no expertise inventories, no rules that cannot be checked.

## Scripts

Add one only when the logic is deterministic and repeated, or fragile enough
that free-hand execution is unreliable.

- Standard library only where possible, so any agent on any machine can run it.
- Clear errors, non-zero exit on failure.
- Never destructive by default: refuse to overwrite, require an explicit flag,
  and refuse to write through a symlink.
- Tested with valid and invalid input before hand-off.

## Trigger testing

Before claiming success, run realistic prompts:

- at least three that must fire;
- at least three near-misses that must not;
- more of both when the skill is broad, destructive, or outward-facing.

A skill that fires on everything is as broken as one that never fires.

## Done means

- `skill_tool.py validate` passes in every target.
- Every script ran, both ways.
- No placeholder text survives.
- The report names the real files, the real commands, and the real results.
