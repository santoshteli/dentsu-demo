module "alb_controller" {
  source = "../../modules/alb-controller"

  name_prefix        = var.project
  controller_version = var.alb_controller_version

  cluster_name      = local.eks.cluster_name
  region            = var.region
  vpc_id            = local.base.vpc_id
  oidc_provider_arn = local.eks.oidc_provider_arn
  oidc_issuer       = local.eks.oidc_issuer

  replica_count = 1

  aws_resource_tags = {
    Env       = var.environment
    Project   = var.project
    ManagedBy = "aws-load-balancer-controller"
  }
}
