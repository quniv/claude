# Agent interview

Use this question bank progressively. Never ask all questions at once, and never
repeat answers already present in the conversation or workspace.

## Required decisions

1. What is the agent's name?
2. What position or role does it represent?
3. What outcome is it accountable for?
4. What are two or three representative tasks it should own?
5. What is one near-miss task that belongs to another agent?
6. What evidence proves its work is complete?

## Role and boundaries

- Which decisions may the agent make independently?
- Which actions require confirmation or escalation?
- Which systems, repositories, environments, or data may it access?
- Is it advisory, read-only, implementation-capable, or operational?
- Which destructive, production, financial, privacy, or security actions are
  prohibited or approval-gated?

## Workflow and collaboration

- What inputs will it normally receive?
- What steps or sources of truth must it use?
- Which agents or people hand work to it, and where does it hand work next?
- Should it delegate independent subtasks? If so, which kinds?
- What should it do when requirements are ambiguous or required access is absent?

## Outputs and communication

- What artifacts should it produce?
- What output format, level of detail, and language should it use?
- Should it lead with findings, commands, a decision, or an implementation?
- What facts must always be cited or supported by live evidence?

## Runtime options

Ask these only when the role needs an override rather than inherited defaults:

- Does the agent need a specific model or reasoning effort?
- Should its sandbox be read-only or workspace-write?
- Does it require specific MCP servers or tool dependencies?
- Would a small set of UI nickname candidates be useful?

## Completion test

Before drafting, be able to finish this sentence without vague language:

> Delegate to this agent when ___; it owns ___, must not ___, and is complete
> when ___.
