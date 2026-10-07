# Deploy-time loading and restart

Contents: host side, pipeline side, restart on Bitbucket, restart on GitHub,
production gate.

## Host side

The deploy script runs on the host as root, reached over SSM `send-command` (no SSH).

```bash
: "${ENV_PARAM_NAME:?ENV_PARAM_NAME is required}"   # no default: dev and prod differ
# Kept for one run: the health check restores it if the new secret breaks the app.
if [ -f app.env ]; then cp -f app.env app.env.prev; fi
( umask 077
  aws ssm get-parameter --name "$ENV_PARAM_NAME" --with-decryption \
    --query Parameter.Value --output text > app.env )
chown <uid>:<uid> app.env   # the container's user, e.g. 1000 for node images
```

When the health check fails, move `app.env.prev` back to `app.env` and start the
previous image again.

```yaml
services:
  api:
    volumes:
      # Mounted, not env_file: Compose would $-interpolate the secret values.
      - ./app.env:/app/.env:ro
```

The app reads `/app/.env` itself, for example with dotenv or pydantic-settings.
A restart mode (`deploy.sh current --skip-migrate`) re-reads the parameter and
recreates the running image, with no build and no migrations.

The host's instance role needs only its own environment:

```hcl
{ Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:<region>:<account>:parameter/<project>/<env>/*" },
{ Effect = "Allow", Action = ["kms:Decrypt"], Resource = "*",
  Condition = { StringEquals = { "kms:ViaService" = "ssm.<region>.amazonaws.com" } } },
```

## Pipeline side

The deploy step maps its deployment environment to the parameter and passes it to
the host command:

```bash
case "$DEPLOY_ENV" in
  production) ENV_PARAM_NAME=/<project>/prod/<service>/env ;;
  dev)        ENV_PARAM_NAME=/<project>/dev/<service>/env ;;
esac
```

Use an OIDC role whose `ssm:SendCommand` is limited to that environment's
instance and the `AWS-RunShellScript` document. After wiring, add the parameter to
`LOADED_BY` in `scripts/secrets.sh`, so a push says when it takes effect.

## Restart on Bitbucket

`assets/restart-bitbucket.just` starts the custom pipeline `restart` through the
Bitbucket API. Define it next to the deploy steps:

```yaml
definitions:
  steps:
    - step: &restart
        name: Pull secrets & restart via SSM
        deployment: Dev
        oidc: true
        script:
          # Reuse the deploy step's anchored script items; only the host command changes.
          - *aws-login
          - export HOST_CMD="ENV_PARAM_NAME=$ENV_PARAM_NAME bash $APP_DIR/scripts/deploy.sh current --skip-migrate"
          - *ssm-run
    - step: &restart-prod
        <<: *restart
        deployment: Production
        trigger: manual

pipelines:
  custom:
    restart:
      - step: *restart
    restart-prod:
      # A pipeline cannot open with a manual step, so this one only states the gate.
      - step:
          name: Gate
          script:
            - echo "Run the next step to restart production with its current secret."
      - step: *restart-prod
```

## Restart on GitHub

`assets/restart-github.just` runs this workflow with `gh workflow run`. Keep
`AWS_DEPLOY_ROLE_ARN`, `EC2_INSTANCE_ID`, `ENV_PARAM_NAME` and `APP_DIR` as
variables of each GitHub environment.

```yaml
name: restart
on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, production]
permissions:
  id-token: write
  contents: read
jobs:
  restart:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
          aws-region: <region>
      - run: |
          id=$(aws ssm send-command --instance-ids "${{ vars.EC2_INSTANCE_ID }}" \
            --document-name AWS-RunShellScript --comment "restart with current secrets" \
            --parameters "commands=[\"ENV_PARAM_NAME=${{ vars.ENV_PARAM_NAME }} bash ${{ vars.APP_DIR }}/scripts/deploy.sh current --skip-migrate\"]" \
            --query Command.CommandId --output text)
          aws ssm wait command-executed --command-id "$id" --instance-id "${{ vars.EC2_INSTANCE_ID }}" || true
          aws ssm get-command-invocation --command-id "$id" --instance-id "${{ vars.EC2_INSTANCE_ID }}" \
            --query '[Status, StandardOutputContent, StandardErrorContent]' --output text
```

## Production gate

Anyone with repo write access, or a token that can run pipelines, can otherwise
restart or redeploy production. Restrict the production environment to admins:

- Bitbucket: deployment permissions on the Production environment (Premium plan).
- GitHub: required reviewers on the `production` environment.
