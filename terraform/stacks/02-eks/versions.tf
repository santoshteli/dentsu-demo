terraform {
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.67.0"
    }
  }

  # The bucket name comes from backend.hcl:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "02-eks/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
