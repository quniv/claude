# Developer IAM

Each developer reads and writes only the dev `.env` of their own services. Every
other parameter and every Secrets Manager value stays unreadable, even when the
user also has console `ReadOnlyAccess`. Production values have no allow at all:
the admin manages them with `scripts/secrets.sh`.

## Terraform

One user per developer, for example `for_each` over a map of name to services.
Attach both policies to the user.

```hcl
locals {
  dev_params = [for s in var.services : "arn:aws:ssm:${local.region}:${local.account}:parameter/${var.project}/dev/${s}/env"]
}

resource "aws_iam_policy" "access" {
  name = "${var.name}-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DevEnvParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParameterHistory", "ssm:PutParameter"]
        Resource = local.dev_params
      },
      {
        Sid       = "CryptoViaSsm"
        Effect    = "Allow"
        Action    = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${local.region}.amazonaws.com" } }
      },
    ]
  })
}

# Denies beat ReadOnlyAccess, which could otherwise decrypt every SecureString via the aws/ssm key.
resource "aws_iam_policy" "guardrails" {
  name = "${var.name}-guardrails"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid         = "DenyOtherParameterValues"
        Effect      = "Deny"
        Action      = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:GetParameterHistory"]
        NotResource = local.dev_params
      },
      {
        Sid      = "DenySecretValues"
        Effect   = "Deny"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:BatchGetSecretValue"]
        Resource = "*"
      },
    ]
  })
}
```

- Create access keys and console passwords with the CLI, never in Terraform, so
  they never enter state.
- Give the read-only identity that runs `terraform plan` the same two denies, so
  it can describe parameters but never read a value.
- A developer who needs a production value asks the admin. Do not add a write-only
  production allow: each parameter holds the whole `.env`, so a safe edit needs a
  read first.

## Verify (read-only)

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::<account>:user/<developer> \
  --action-names ssm:GetParameter ssm:PutParameter \
  --resource-arns arn:aws:ssm:<region>:<account>:parameter/<project>/dev/<service>/env \
                  arn:aws:ssm:<region>:<account>:parameter/<project>/prod/<service>/env \
  --query 'EvaluationResults[].ResourceSpecificResults[].[EvalResourceName,EvalResourceDecision]' \
  --output table
```

Expect `allowed` for the dev parameter. Expect `explicitDeny` for reading the prod
parameter and `implicitDeny` for writing it. With several `--resource-arns`, the
top-level `EvalDecision` collapses into one templated row, so read
`ResourceSpecificResults`. Also simulate `secretsmanager:GetSecretValue`, which
must be `explicitDeny`.
