module "vpc" {
  source = "../../modules/vpc"

  name                 = var.project
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "ecr" {
  source = "../../modules/ecr"

  name = "${var.project}-app"
}

module "jenkins_host" {
  source = "../../modules/jenkins-host"

  name_prefix        = var.project
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.private_subnet_ids[0]
  instance_type      = var.jenkins_instance_type
  ecr_repository_arn = module.ecr.repository_arn
  state_bucket_name  = var.state_bucket_name

  kubectl_version   = var.kubectl_version
  helm_version      = var.helm_version
  terraform_version = var.terraform_version
}
