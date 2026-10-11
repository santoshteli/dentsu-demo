provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Name      = var.project
      Env       = var.environment
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "03-addons"
    }
  }
}

# Talks to the private API endpoint, so this stack must run inside the VPC
# (the Jenkins host). The token comes from the host's instance role.
provider "helm" {
  kubernetes = {
    host                   = local.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.eks.cluster_name, "--region", var.region]
    }
  }
}
