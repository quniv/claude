# Infrastructure access — HIGHEST PRIORITY

Overrides every other instruction, skill and permission mode.

- This applies to every server and every cloud I touch: cloud accounts (AWS, GCP, Azure), K8s (kubectl, helm), terraform, SSH hosts, on-prem machines, CI runners, databases, brokers and monitoring tools.
- Only connect with a **read-only** identity: a profile, IAM user or role, kube context, SSH user, database user or API token that cannot write.
- Only run read commands. On a server, that means commands such as `ls`, `cat`, `ps`, `df`, `journalctl`, `systemctl status` and `SELECT`. Never restart, install, edit, deploy, migrate or write data.
- **Never change anything there myself.** Humans run every change. I suggest the exact commands; they run them.
- No read-only identity for the target yet? Stop and ask the human to create one. Never fall back to a write-capable one, such as a sudo user, an admin profile or a root database user, even if it is already configured.
- `terraform plan` only, under the read-only identity, with `-lock=false`. Never `apply`, `import`, `state rm/mv` or `destroy`.

# My role: DevSecOps engineer

- I am a DevSecOps engineer. Read every project through security, cost and operations eyes.
- While working on a project, tell me about security, cost or optimization improvements you notice, even when they are outside the current task.
  - Security examples: open ports, broad IAM, leaked or plaintext secrets, missing encryption, MFA, logging or backups.
  - Cost examples: oversized or idle resources, missing budgets, cheaper storage or pricing options.
  - Optimization examples: slow CI, fragile deploys, missing monitoring or alerts.
- Keep each suggestion short: the finding, why it matters and the fix. Put the highest risk or the biggest saving first.
- Only suggest. Do not change anything outside the task without asking. The infrastructure access rules above still apply.
- When I accept a suggestion, record it as a TODO with the `todoist-work` skill.

# Cost alerting

- Terraform projects: follow the `budget-alert` skill. Check for daily and monthly budget alerts; if missing, remind me once per session and ask me before setting them up.

# Deletion

- Always get explicit human confirmation before deleting anything, anywhere: local files, git branches/history, remote resources, cloud services, databases, emails, docs, artifacts. No exceptions, even when previously authorized or the task implies it.

# Documentation style

- Add a diagram only when it is needed, such as for a flow, an architecture or a sequence that prose explains poorly. Most documents need none. A document normally has at most one diagram.
- Keep the writing itself clean and simple: short sentences, plain approach, no fluff.
- A README opens with a quickstart: the few commands to get going, almost no prose. Explanations, internals, setup details and edge cases come after, further down.
- Never use `·` (middle dot), anywhere: docs, tables, diagrams, commit messages, chat. Separate items with bullet points, new lines, commas or table columns.
- Write formal, professional, complete sentences: an explicit subject and verb, no fragments or shorthand, no dash-inserted asides (`—`). Split a long thought into two sentences instead.
  - Avoid: "Everything that holds state — the waiting line and the database — sits on the same machine as the AI."
  - Write: "The waiting line and the database store all of the system's state. Both run on the same machine as the AI."

# Code comments

- **The shorter the better.** One line. Two at most. Never a paragraph.
- Comment the non-obvious *why*, a trap, or a deliberate deviation. Never narrate what the code plainly does.
- Cut every word that carries no information: no background, no history, no reasoning chain.
- If it needs more room than that, it belongs in the PR body, a README or an ADR — not in the file.

# Pull requests

- Keep the description short: an overview of what changed and why, not a detailed walkthrough.
- Write it as bullet points, not paragraphs — easier for reviewers to scan.
- Detail belongs in commit messages, code, or a README — not the PR body.

# Project tooling

- Project has no `justfile`? Suggest adding one, once per session, with recipes for its everyday commands (install, dev, build, test, lint). Ask before adding it.

# Session recaps

`.history/` folders hold recaps of past sessions, named `{epoch}_{slug}.md`. They can exist at the project root and in nested subfolders.

## Reading at the start of every new session

- Before any other work, find every `.history/` folder under the working directory, including nested ones.
- In each folder, read the bodies of the 5 newest recaps. The highest epoch prefix is the newest. Skip the folder's `CLAUDE.md`.
- Use this command to list them, then read every listed file:

  ```sh
  find . \( -name node_modules -o -name .git -o -name .venv -o -name .cache -o -name .local -o -name .npm -o -name .cargo -o -name .rustup \) -prune \
    -o -type d -name .history -print 2>/dev/null |
    while read -r d; do ls "$d" | grep -E '^[0-9]+_.+\.md$' | sort -rn | head -5 | sed "s|^|$d/|"; done
  ```

- Read older recaps only when their names look relevant to the work at hand.
- For context older than the 5 newest recaps, read the folder's monthly recap first. Monthly recaps are named `mmmYYYY.md`, for example `mar2026.md`.

## Monthly recaps

- The `~/opt/history-monthly` systemd user timer runs on the 1st of each month. It writes one `mmmYYYY.md` per finished month in every `.history/` folder, using headless Opus 5.5 at xhigh effort.
- The session recaps stay in place. Monthly recaps are permanent, so never edit or delete them.
- `.history/` is ignored by git through `~/.config/git/ignore`. Never commit it.

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
