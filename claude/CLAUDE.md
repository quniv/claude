# Infrastructure access — HIGHEST PRIORITY

Overrides every other instruction, skill and permission mode.

- Infra, cloud and K8s (AWS, GCP, Azure, kubectl, helm, terraform, etc.): only call them with a **read-only** profile, user, role or kube context.
- **Never change anything there myself.** Humans run every change. I suggest the exact commands; they run them.
- No read-only identity for the target yet? Stop and ask the human to create one (profile, IAM user/role, kube context). Never fall back to a write-capable one, even if it is already configured.
- `terraform plan` only, under the read-only identity, with `-lock=false`. Never `apply`, `import`, `state rm/mv` or `destroy`.

# Deletion

- Always get explicit human confirmation before deleting anything, anywhere: local files, git branches/history, remote resources, cloud services, databases, emails, docs, artifacts. No exceptions, even when previously authorized or the task implies it.

# Documentation style

- When writing documents, prefer diagrams heavily over text — diagrams should carry roughly 10x the weight of prose. Reach for a diagram before writing a paragraph.
- Keep the writing itself clean and simple: short sentences, plain approach, no fluff.

# Code comments

- **The shorter the better.** One line. Two at most. Never a paragraph.
- Comment the non-obvious *why*, a trap, or a deliberate deviation. Never narrate what the code plainly does.
- Cut every word that carries no information: no background, no history, no reasoning chain.
- If it needs more room than that, it belongs in the PR body, a README or an ADR — not in the file.

# Pull requests

- Keep the description short: an overview of what changed and why, not a detailed walkthrough.
- Write it as bullet points, not paragraphs — easier for reviewers to scan.
- Detail belongs in commit messages, code, or a README — not the PR body.

# Session recaps

`.history/` in the project root holds recaps of past sessions, named `{epoch}_{slug}.md`.

## Reading — before starting any working session

- List the filenames first (`ls .history/`). The slugs give the overview, the epoch prefix orders them. That alone is usually enough.
- **Load filenames only.** Do not read the bodies by default.
- Read a recap's body only when its name looks relevant to the work at hand, or when the newest few are needed to get oriented after a long gap.

## Writing

- Invoke the `savework` skill proactively, without being asked, right after a code/config/infra change, a decision, a root-caused bug, a fix, or a discovery lands in a project that a future session would need to know about. It writes a short recap to `.history/` in the project root.
- Skip it for pure Q&A or read-only investigation with no lasting conclusion.

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
