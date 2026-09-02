# Capability decisions

Settle these before writing. Each has a default; deviate only with a reason you
can state.

## Tools — default: inherit everything

Narrow the allowlist only when narrowing is the point:

- **Read-only roles** (reviewers, auditors, explainers) — restrict to reading
  and searching. This is the case where an allowlist genuinely adds safety.
- **Roles adjacent to destructive work** — withhold the tool that does the
  damage, and say in the body that the agent reports rather than acts.

Otherwise inherit. The common failure is an allowlist written from imagination
that omits a tool the role actually needs; the agent then fails in a way that
looks like a model problem rather than a config problem.

Claude Code takes `tools` as a comma-separated frontmatter list. Codex governs
tool access through its permissions and sandbox configuration rather than a
per-role list, so an equivalent restriction may need a `config_file` layer —
say so plainly instead of implying the two are symmetrical.

## Model — default: inherit

Override when the role is either much cheaper or much harder than the parent's
default work:

- A high-volume, mechanical role can drop to a smaller model.
- A role whose whole value is careful judgement can raise reasoning effort.

Claude Code: `model: sonnet | opus | haiku | inherit`.
Codex: `model` and `model_reasoning_effort`.

Never override to a model you have not confirmed exists.

## Skills — reference by name, do not link

Both tools discover skills by matching descriptions at run time from their own
skill directories. So:

- Name the skills the role should lean on, in the body, and say when.
- Do not create symlinks into the agent's directory. Neither tool reads a
  per-agent skill folder, so the links are inert and mislead the next reader.
- If the role needs a skill that does not exist, say so and offer to create it
  with `create-skill` — do not create it unasked.

## Description — the delegation trigger

The parent reads only this. It must answer "should I hand this to that agent?"

- Weak: `An expert in Terraform and cloud infrastructure.`
- Strong: `Reviews Terraform plans for destructive changes before apply.
  Delegate when a plan needs a safety check. Does not run apply or destroy.`

Include the exclusion when a neighbouring agent exists.

## Body — what actually earns its place

Keep: the mission, the explicit exclusions, the ordered procedure, the approval
points, the failure behaviour, the hand-off format.

Cut: persona, seniority, adjectives about quality, restatements of the tool's
own defaults, and any rule you could not check after the fact.
