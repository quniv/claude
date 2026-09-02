# Interview questions

Ask one to three at a time. Ask only what you cannot already answer.

## Mission and boundary

- In one sentence, what does this agent own?
- Name a task it should refuse and hand back. Why that one?
- When should the parent session do the work itself instead of delegating?
- Is there an existing agent or skill this overlaps with?

## Real work

- Describe the last time you did this task. What did it involve?
- What does the agent need to read before it can start?
- Which judgement calls should it make alone, and which must come back to you?
- What does it get wrong if nobody constrains it?

## Access

- Which tools does it need — read-only, or does it write, run, or install?
- Anything destructive or outward-facing: pushes, deploys, deletes, messages?
- Should it be able to spawn further agents?
- Does it need credentials or network access?

## Output

- What does it hand back — a report, a diff, a file, a decision?
- What must always be in that hand-off, even when everything went fine?
- How would you tell a good run from a bad one?

## Model and cost

- Is this latency-sensitive, or does it deserve more reasoning?
- Will it run often enough that model choice matters?
- Any reason not to inherit the parent's settings?

## Scope pressure

- Is this one role, or two wearing one name?
- If it could only do one thing, which?
