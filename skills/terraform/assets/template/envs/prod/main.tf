# Same account as the other environments, so allowed_account_ids cannot tell
# them apart -- every resource here must carry the environment in its name.

locals {
  env        = "prod"
  account_id = "__ACCOUNT_ID__"
  region     = "__REGION__"
}

# Resources and module calls for prod go here, or in topic files (network.tf, iam.tf, ...).
