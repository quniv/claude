# Skill interview

Use this question bank progressively. Ask one to three high-value questions at a
time and do not repeat facts already supplied or discoverable in the workspace.

## Required decisions

1. What is the proposed skill name?
2. What are two realistic requests that should trigger it?
3. What is one similar request that should not trigger it?
4. What output or changed artifact should each successful run produce?
5. What evidence proves the workflow completed correctly?

## Inputs and workflow

- What files, data, arguments, or conversation context will it receive?
- Which sources of truth must it inspect before acting?
- What sequence is essential, and where may the agent exercise judgment?
- Which defaults should it choose without presenting a menu?
- Which tools, CLIs, libraries, APIs, or MCP servers should it use?
- What should happen when required input, access, or tooling is missing?

## Scope and safety

- Is the skill advisory, read-only, mutating, or operational?
- Which actions are destructive, production-facing, security-sensitive, private,
  expensive, or approval-gated?
- What work belongs to an adjacent skill instead?
- Must compatibility, historical behavior, formatting, or existing user changes
  be preserved?

## Reusable contents

- Does the workflow repeatedly reinvent deterministic logic that merits a tested
  script?
- Is there detailed domain knowledge that should live in a conditional reference?
- Are there templates, schemas, icons, boilerplate, or other output assets to
  bundle?
- Which examples clarify behavior without becoming generic documentation?

## Delivery and evaluation

- Who will invoke the skill and from which workspace or client?
- Should implicit invocation be allowed, or only explicit `$skill-name` use?
- Which output format and communication style are required?
- What valid, invalid, edge-case, should-trigger, and should-not-trigger cases
  should be tested?

## Completion test

Before drafting, be able to finish this sentence precisely:

> Use this skill when ___ to produce ___ by following ___; do not use it for ___,
> and consider it complete only when ___.
