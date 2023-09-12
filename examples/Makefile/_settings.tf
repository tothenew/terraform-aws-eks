
provider "aws" {
  region  = local.workspace["aws"]["region"]
}

locals {
  env       = yamldecode(file("${path.module}/config.yml"))
  common    = local.env["common"]
  workspace = local.env["workspaces"][terraform.workspace]

  project_name_prefix = "{local.workspace.account_name}-${local.workspace.aws.region}-${local.workspace.project_name}"

  tags = {
    Project     = local.workspace.project_name
  }
}