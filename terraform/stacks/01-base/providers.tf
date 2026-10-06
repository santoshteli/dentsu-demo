provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Name      = var.project
      Env       = var.environment
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "01-base"
    }
  }
}
