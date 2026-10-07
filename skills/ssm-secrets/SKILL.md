---
name: ssm-secrets
description: Set up or extend a project's .env secrets in AWS SSM Parameter Store, managed through just recipes. Each service keeps its whole .env as one SecureString per environment. An admin syncs every environment from a git-ignored secrets/ folder, with version-guarded pushes, a typed prod confirmation and key names only in output. Developers pull and push only the dev value, the deploy writes it onto the Docker host, and `just restart` reloads it. Use when an AWS project needs a .env or secrets workflow, when adding a service or environment to one, or when porting this setup to another repo. Not for Vault, SOPS, Kubernetes Secrets, app-level secret SDKs or non-AWS clouds.
---

# SSM Secrets

## The pattern

| Layer | Where | Role |
|---|---|---|
| Store | SSM `/<project>/<env>/<service>/env` | One SecureString per service and environment holds the whole `.env`. Other secrets go to Secrets Manager as `<project>/<env>/<name>`. |
| Admin | admin repo: `scripts/secrets.sh` and `secrets-*` recipes | Mirrors one environment at a time into the git-ignored `secrets/` folder. |
| Developers | each service repo: `env-*` and `restart` recipes | Pull, diff and push the dev value only, then restart dev. |
| IAM | Terraform | Developers reach only their dev values. Everything else is denied. |
| Deploy | the service's deploy script and compose file | Writes the value to `app.env` on the host and mounts it read-only. |

## Gather first

Ask only for what the repos do not already show:

- The project prefix (lowercase, such as `acme`), the AWS region and each environment's account ID.
- The services, their repos and which repo is the admin (infra) repo.
- The dev branch, the CI system (Bitbucket or GitHub), and the container user ID and app directory on the host.

## Set up

Replace the placeholders `__PROJECT__`, `__REGION__`, `__DEV_ACCOUNT_ID__`, `__PROD_ACCOUNT_ID__`, `__SERVICE__`, `__DEV_BRANCH__` and `__BITBUCKET_REPO__` (`workspace/repo`). Afterwards, `grep -n '__[A-Z_]*__'` on each copied file must print nothing.

1. **Admin repo.** Copy `assets/secrets.sh` to `scripts/secrets.sh` and make it executable. Append `assets/infra.just` to the justfile. Add `/secrets/` to `.gitignore`. Add any further environment to `ACCOUNTS`.
2. **Each service repo.** Append `assets/app.just` and the CI's restart recipe (`assets/restart-bitbucket.just` or `assets/restart-github.just`) to the justfile. A new justfile also needs a `default` recipe that runs `@just --list --unsorted`. Ignore `.env.dev` and `.env.dev.version` in git. Put `just env-pull`, `just env-push` and `just restart` in the README quickstart.
3. **Developer IAM.** Read [references/developer-iam.md](references/developer-iam.md).
4. **Deploy and restart.** Read [references/deploy.md](references/deploy.md). Then list every wired parameter in `LOADED_BY` in `scripts/secrets.sh`.

In a project that already keeps values in SSM, add only the missing pieces and keep its existing parameter names. A new name means a new parameter and a deploy change.

## Verify

- Run `shellcheck -S warning scripts/secrets.sh` and `bash -n` on it, and `just --list` in every repo you touched.
- Run the read-only IAM simulation from developer-iam.md.
- Hand the first `just secrets-pull <env>`, `secrets-status` and `secrets-push` to the human. These recipes, the `env-*` recipes and `just restart` decrypt secrets or restart services. Do not run them yourself, and never print, log or commit a secret value.

## Keep these when adapting

- Values never reach argv, logs or chat. Upload with `file://`, compare in a private temp directory and print key names only.
- A push is refused when AWS changed since the last pull (`secrets/.versions` and `.env.dev.version` record the pulled version).
- Prod writes need `prod` typed, not `y`. Every command checks that `AWS_PROFILE` points at that environment's account.
- `secrets/` holds plaintext. Keep `umask 077`, its own `.gitignore` containing `*`, and full-disk encryption.
- Secrets Manager secrets that a service owns (such as RDS `rds!db-...`) are never synced.
- Values stay out of Terraform. Create no `aws_ssm_parameter` for these names, so plan identities can be denied secret values.
- Console `ReadOnlyAccess` can decrypt every SecureString through the `aws/ssm` key, so developer users need the explicit denies.
- Mount the file into the container. Compose `env_file` interpolates `$` inside secret values.
- A restart re-reads the value without a build or migrations. Production restarts need an admin gate (see deploy.md).
