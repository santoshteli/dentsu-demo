# Outputs of stack 01-base: VPC, subnets, Jenkins security group and role.
data "terraform_remote_state" "base" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "01-base/terraform.tfstate"
    region = var.region
  }
}

locals {
  base = data.terraform_remote_state.base.outputs
}
