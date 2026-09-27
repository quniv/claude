# Same account as the other environments, so allowed_account_ids cannot tell
# them apart -- every resource here must carry the environment in its name.

locals {
  env        = "stg"
  account_id = "__ACCOUNT_ID__"
  region     = "__REGION__"
}

# Resources and module calls for stg go here, or in topic files (network.tf, iam.tf, ...).
