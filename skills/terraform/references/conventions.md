# Boilerplate conventions

Contents: [Layout](#layout) · [State](#state) · [Where things go](#where-things-go) ·
[Modules](#modules) · [Commands](#commands) ·
[Bootstrap](#bootstrap) · [Style](#style)

## Layout

```
shared/           account-wide stack, applied before the environments
envs/<env>/       one root module per environment (stg, prod)
modules/<name>/   reusable, consumed via `source = "../../modules/<name>"`
scripts/          aws-inventory.sh: read-only sweep → import scaffolding
justfile          every command
```

A **stack** is a directory. Environments are separated by directory, never by
`terraform workspace`. All environments may share one AWS account, so every
resource name carries the environment (`<prefix>-<env>-...`) and
`allowed_account_ids` pins the account in every provider block.

## State

- One S3 bucket for every stack, keyed by path: `shared/terraform.tfstate`,
  `envs/<env>/terraform.tfstate`.
- Locking is native: `use_lockfile = true`, no DynamoDB table. It requires
  `required_version = ">= 1.11"` (experimental in 1.10).
- The bucket must exist before any stack inits. When Terraform manages it,
  `shared/` owns it and starts on local state; see [Bootstrap](#bootstrap).

## Where things go

| New thing | Goes in |
|---|---|
| Resource used by one environment | `envs/<env>/main.tf` (or a topic file like `iam.tf`) |
| Account-wide IAM, users, cross-env policies | `shared/` |
| Pattern repeated across envs | `modules/<name>/`, called from each env |
| Import blocks during adoption | `<stack>/imports.tf`, deleted once applied |
| Adopted policy documents | `<stack>/policies/<name>.json`, verbatim |

- Environment values live in a `locals` block at the top of `envs/<env>/main.tf`
  (`env`, `account_id`, `region`, CIDRs, ...). Resources owned elsewhere (e.g.
  a CloudFormation stack) are referenced from a `local` map of IDs.
- Maps, not lists, for anything keyed (subnets by AZ, rules by name): deleting
  one list element renumbers the rest and Terraform recreates them.
- A new environment: copy `envs/stg/`, change `local.env` and the backend
  `key`, add the stack to the justfile's `stacks`.

## Modules

- One directory per module under `modules/`, each with `main.tf`,
  `variables.tf`, `outputs.tf` and `versions.tf`, and no provider block. Lock
  files are committed only in root stacks; `modules/*/.terraform.lock.hcl` is
  gitignored.
- Create a module only for a pattern repeated across stacks. A one-off resource
  belongs directly in its stack.
- Defaults are the hardened greenfield choice (encryption on, IMDSv2 required,
  no public IPs). A setting that exists only to import a live resource unchanged
  must default to that same hardened behaviour, so existing callers still plan
  clean. After changing a module, re-plan every stack that calls it.
- Security group rules as standalone `aws_vpc_security_group_{ingress,egress}_rule`
  resources: inline rule blocks churn every plan and cannot be imported one at
  a time. `create_before_destroy` on groups.
- Long-lived hosts: `ignore_changes = [ami, user_data]`, so a newer AMI or an edited
  bootstrap script never silently replaces or restarts a running host.

## Commands

```bash
export AWS_PROFILE=<profile>
just init envs/stg
just plan envs/stg               # extra flags pass through: -target=module.x
just plan-ro envs/prod           # readonly role: cannot take the lock
just check                       # fmt-check + validate (offline)
just fmt · just lint             # tflint --recursive
just inventory                   # scripts/aws-inventory.sh (read-only)
```

## Bootstrap

```bash
just bootstrap                  # shared/ on local state
# add the backend "s3" block to shared/
just migrate-state              # move shared/ state into the bucket
```

Do apply and migrate in one sitting; until then state sits on one laptop.

## Style

- Comments: one or two lines, only the non-obvious *why* or a trap.
- `terraform fmt` clean; `tflint` recommended preset + AWS ruleset.
- Docs favour diagrams over prose.
