module "eks" {
  source = "../../modules/eks"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = local.base.private_subnet_ids

  # The Jenkins host runs Terraform (stack 03), kubectl and the pipeline.
  api_access_security_group_ids = [local.base.jenkins_security_group_id]
  admin_principal_arns          = concat([local.base.jenkins_role_arn], var.additional_admin_principal_arns)
}

module "nodegroup" {
  source = "../../modules/nodegroup"

  name               = var.project
  cluster_name       = module.eks.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = local.base.private_subnet_ids

  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types
  min_size       = var.node_min_size
  desired_size   = var.node_desired_size
  max_size       = var.node_max_size
  disk_size      = var.node_disk_size

  # Nodes only become Ready once the CNI is running on them.
  depends_on = [aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
}
