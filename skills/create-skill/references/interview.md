# Interview questions

Ask one to three at a time. Ask only what you cannot already answer. Stop as
soon as the boundary is sharp enough that a different agent would not guess
differently.

## Triggering

- Give me two requests, in your own words, that should invoke this skill.
- Give me one that feels close but must **not** invoke it. What separates them?
- Should it fire on its own when the description matches, or only when invoked
  explicitly?
- Is there an existing skill or command a user might reach for instead?

## Workflow

- Walk me through the last time you did this by hand. What did you actually do?
- Which step do you or the agent get wrong most often?
- What is the source of truth — a file, a command's output, an API, a person?
- Which steps are strictly ordered, and which can happen in any order?

## Inputs and outputs

- What must exist before this can start? What should happen when it does not?
- What is the finished artifact — a file, a commit, a report, a changed system?
- How do you know it worked? What would you check?
- What should never be produced or touched?

## Tools and permissions

- Which commands or tools does this need?
- Anything destructive, irreversible, or outward-facing — writes to a shared
  system, pushes, deletes, sends?
- What needs explicit approval every single time?
- Any credentials or network access involved?

## Failure

- What are the realistic failure modes?
- On failure, should it stop, retry, or fall back — and to what?
- What must be reported even when everything succeeds?

## Scope pressure

Ask these when the skill is growing past one coherent workflow:

- Is this one skill, or two that share a name?
- Which part is the piece you actually repeat?
- What would you drop if you could only keep half of it?
