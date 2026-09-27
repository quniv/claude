---
name: terraform
description: Works in an AWS Terraform boilerplate built from directory stacks — shared/ for account-wide resources, per-environment envs/ root modules, and reusable modules/. It has one S3 backend with native lockfile locking, and a justfile that runs every command. Use it to scaffold a new infrastructure repo from this boilerplate, to add resources, modules or environments to a repo with this layout, or to adopt existing hand-built AWS resources into shared/ or envs/ with import blocks, from one host to every IAM user in the account, so the first plan changes nothing. Not for general Terraform questions, other clouds, provider development, HCP Terraform Stacks, or repos with a different layout unless asked to migrate them to it.
---

# Terraform boilerplate

Work the way this boilerplate works, so a human reviewer sees small, predictable
plans. Identify the mode, read only its reference, and keep the rules below on
every run.

## Modes

| Situation | Do |
|---|---|
| No repo yet, or an empty one | Scaffold: run `scripts/scaffold.sh` (below) |
| Repo has `shared/`, `envs/`, `modules/`, `justfile` | Extend: read [references/conventions.md](references/conventions.md) |
| Resources already exist in AWS and must come under Terraform | Adopt: read [references/adoption.md](references/adoption.md) (and conventions.md for placement) |

A repo with a different layout is not this boilerplate: follow its own
conventions unless asked to migrate it.

## Rules for every run

- **The human runs `plan` and `apply`.** Never apply. Run a plan only when asked,
  and then only with read-only credentials (`just plan-ro`).
- **Read AWS with read-only credentials only.** Never read or record secret
  values, instance user_data, private keys or state contents into the repo or
  the chat.
- **Everything through `just`.** Run `just check` (fmt + offline validate) before
  handing over.
- **Place by ownership**: one environment → `envs/<env>/`; account-wide →
  `shared/`; repeated pattern → `modules/`. Resources another tool owns
  (CloudFormation/CDK, AWS services) are referenced by ID, never imported.
- **Modules stay hardened by default.** A new variable defaults to the existing
  behaviour; after changing a module, every stack using it must still plan clean.
- **Adoption writes nothing to AWS.** Match live values exactly, including typos;
  never "fix" a resource while importing it. Improvements are separate changes.
- **Import blocks leave only after their own apply.** Removing one earlier makes
  the plan create a duplicate of a running resource.
- Comments: one or two lines, only the non-obvious why. No secrets, `*.tfvars`
  or state in git.

## Scaffold

```bash
scripts/scaffold.sh <dest> --prefix acme --account-id 123456789012 \
  --region eu-west-1 --github-org acme-inc --github-repo acme-terraform \
  [--aws-profile acme]
```

It copies [assets/template/](assets/template/) (empty shared/ and modules/,
envs/stg, envs/prod, justfile, inventory script), fills every `__TOKEN__`, and
refuses a non-empty destination or a leftover token. Then run `just check` in
the new repo and hand the human the bootstrap steps from its README.

## Handover

End every change with:

1. Files changed and why, one line each.
2. Per stack, the exact plan to expect, e.g.
   `envs/stg: 12 to import, 0 to add, 0 to change, 0 to destroy`.
3. The commands the human runs, in order.
4. Anything found but deliberately not changed (security findings, drift,
   resources owned elsewhere).
