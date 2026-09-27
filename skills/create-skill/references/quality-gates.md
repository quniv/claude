# Skill quality gates

Apply every relevant gate before declaring a generated skill complete.

## Scope and value

- Encapsulate one coherent workflow that composes with other skills.
- Ground instructions in real tasks, project artifacts, corrections, and current
  primary documentation rather than generic model knowledge.
- Add information the agent would otherwise miss; remove explanations it already
  knows.
- Choose a default approach. Mention an alternative only for a defined exception.
- Match specificity to fragility: flexible reasoning for open-ended work and
  deterministic commands or scripts for narrow, failure-prone operations.

## Discovery metadata

- Match frontmatter `name` to the directory exactly.
- Describe the user's intent, what the skill does, and when to use it.
- Front-load distinctive trigger language so truncation does not hide it.
- State important near-miss boundaries concisely when false triggering is likely.
- Keep the description within the current specification limit.
- Keep `agents/openai.yaml` consistent with `SKILL.md`; make the default prompt
  mention `$skill-name` explicitly.

## Progressive disclosure

- Keep the main instructions concise and below current line and token limits.
- Put non-obvious gotchas needed on every run in `SKILL.md`.
- Put detailed conditional knowledge in focused `references/` files.
- Tell the agent exactly when to read each reference.
- Keep references one level from `SKILL.md`; give files over 100 lines a contents
  overview.
- Avoid duplicating the same guidance in the body and references.

## Resources and dependencies

- Include only resource directories that are actually used.
- Make scripts self-contained, defensive, and clear about dependencies and
  failures. Test valid, invalid, and edge cases.
- Use assets as output inputs, not as hidden instruction files.
- Declare MCP dependencies in `agents/openai.yaml` only when the skill truly
  requires them.
- Do not add icons, brand colors, or other optional UI fields without user input.

## Trigger evaluation

Create realistic prompts with paths, context, casual phrasing, and near misses.
For complex trigger behavior, aim for roughly 8-10 should-trigger and 8-10
should-not-trigger prompts. Split them into a fixed training set and a held-out
validation set. Revise from training failures and choose the description that
performs best on validation, not merely the last revision.

If runs are nondeterministic, test each prompt multiple times and compare trigger
rates. Do not leak validation results into description revisions.

## Behavioral evaluation

- Define objective assertions for artifacts, commands, required evidence, and
  prohibited behavior.
- Compare output with and without the skill when practical; keep the skill only
  if it adds measurable value.
- Inspect execution traces for wasted steps, ignored constraints, unsafe actions,
  and repeated logic that should become a script.
- Forward-test using raw tasks and artifacts. Do not tell the evaluator the
  intended answer, suspected bug, or desired fix.

## Final safety

- Leave no TODOs, placeholder examples, broken links, or untested scripts.
- Preserve unrelated working-tree changes.
- Do not install public dependencies or skills without explicit approval.
- Report what remains unverified because of unavailable tools, credentials,
  network, or runtime access.
