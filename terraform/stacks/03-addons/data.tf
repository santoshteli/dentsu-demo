# Outputs of stack 01-base (VPC) and stack 02-eks (cluster and OIDC provider).
data "terraform_remote_state" "base" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "01-base/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "02-eks/terraform.tfstate"
    region = var.region
  }
}

locals {
  base = data.terraform_remote_state.base.outputs
  eks  = data.terraform_remote_state.eks.outputs
}
