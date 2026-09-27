# __GITHUB_REPO__

One AWS account (`__ACCOUNT_ID__`, `__REGION__`), two environments: **stg** and **prod**.

```
shared/         account-wide stack, applied before the environments
envs/stg/       root module, state key envs/stg/terraform.tfstate
envs/prod/      root module, state key envs/prod/terraform.tfstate
modules/        reusable modules, called from the env stacks
scripts/        aws-inventory.sh -- read-only sweep that scaffolds import blocks
justfile        every command
```

One bucket holds all state, separated by key, locked natively (`use_lockfile`).
Environments are directories, not workspaces.

## Bootstrap

```mermaid
graph LR
  A["1 · shared/<br/>local state"] --> B["2 · add backend s3<br/>just migrate-state"]
  B --> C["3 · envs/stg · envs/prod"]
```

```bash
export AWS_PROFILE=__AWS_PROFILE__

just bootstrap          # shared/ on local state
just migrate-state      # after adding its backend "s3" block
```

The state bucket `__PREFIX__-tfstate-__ACCOUNT_ID__` must exist before the
environments init.

## Commands

```bash
just                    # list recipes
just plan envs/stg
just plan-ro envs/prod  # readonly role: no state lock
just check              # fmt-check + validate, offline
```

