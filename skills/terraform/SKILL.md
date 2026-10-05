---
name: terraform
description: House rules for Terraform code — file layout by AWS service, naming, renames and verification. Use whenever writing, reviewing, refactoring, importing or adding .tf files or Terraform modules, and before placing a new resource in a stack.
---

# Terraform house rules

## File layout: one file per AWS service

Every stack directory uses the same file names. A resource goes in the file of the
service it belongs to, and a module call goes in the file of the service it creates.

| File | Holds |
|---|---|
| `versions.tf` | `terraform {}`, backend, providers |
| `main.tf` | stack-wide locals only (env, account, region, shared shorthands) |
| `outputs.tf` | outputs |
| `imports.tf` | import blocks; temporary, delete once applied and re-planned clean |
| `vpc.tf` | VPC, subnets, IGW, NAT, route tables, routes, associations, VPC endpoints, flow logs, network modules |
| `ec2.tf` | instances and host modules, security groups and their rules/modules, Elastic IPs, key pairs, launch templates, Auto Scaling groups/policies, **load balancers, target groups, listeners, listener rules/certificates**, EBS account settings |
| `rds.tf` | DB instances and DB modules, DB subnet groups, DB parameter groups |
| `<service>.tf` | everything else, one file per service: `iam.tf`, `s3.tf`, `lambda.tf`, `cloudwatch.tf` (log groups, metric filters, alarms, dashboards), `eventbridge.tf`, `sns.tf`, `ssm.tf`, `secretsmanager.tf`, `route53.tf`, `acm.tf`, `cloudfront.tf`, `waf.tf`, `efs.tf`, `docdb.tf`, `dms.tf`, `guardduty.tf`, `securityhub.tf`, `inspector.tf`, `config.tf`, `cloudtrail.tf`, `accessanalyzer.tf`, `budgets.tf` |

- One file per service. Never split a service into topic files, and never name a
  file by theme (`edge.tf`, `observability.tf`, `network-extra.tf`) or by project (`chirpstack.tf`).
- Locals and data sources live with their main consumer (`aws_iam_policy_document` → `iam.tf`).
- Other regions go in the same service file, under a `# --- us-east-1 ---` section,
  after the stack's home region.
- Each file opens with a one-line header naming what it holds.

## Naming

- Never use "adopt"/"adopted"/"adoption" in file names, provider aliases,
  resource/module/local names or comments. Name what a thing *is*, not how it got
  into Terraform. Say "import"/"imported" when the history matters.
- Resource names are short and specific (`aws_lb.prod`, `aws_subnet.prod["private_1"]`);
  don't repeat the type (`aws_s3_bucket.bucket`, `aws_guardduty_detector.guardduty`).
- Provider aliases describe the difference: region (`use1`, `apse1`) or behaviour (`untagged`).

## Changing code safely

| Change | Rule |
|---|---|
| Move a block to another file | Free; addresses don't depend on file names. |
| Rename a resource or module | Add a `moved {}` block; remove it after the apply that records the move. |
| Change a resource's provider alias | Same provider type and region only; confirm with a plan. |
| Import | Write code + import block, plan until only imports remain, apply, re-plan, then delete the import block. |

Every refactor ends with `terraform fmt -recursive`, `validate`, and a plan per
stack showing `0 to add, 0 to change, 0 to destroy` (moves allowed).

## Comments

One or two lines, only for a non-obvious why, a trap, or a recorded finding
("recorded, not endorsed"). No narration of what the code plainly does.

## Cost alerting

Every Terraform project needs a daily and a monthly budget alert. Follow the
`budget-alert` skill: check for one, remind once per session if missing, and ask
the user before setting it up.
