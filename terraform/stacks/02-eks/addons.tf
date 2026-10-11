# Add-ons live in the stack because their order spans both modules:
#   cluster -> vpc-cni, kube-proxy -> node group -> CoreDNS
# vpc-cni and kube-proxy are DaemonSets, so they install cleanly with no nodes.
# CoreDNS is a Deployment and needs a node to schedule on, otherwise the
# add-on stays DEGRADED until Terraform times out.

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "vpc-cni"
  addon_version = var.addon_versions["vpc-cni"]

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = { Name = "${var.cluster_name}-vpc-cni" }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "kube-proxy"
  addon_version = var.addon_versions["kube-proxy"]

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = { Name = "${var.cluster_name}-kube-proxy" }
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "coredns"
  addon_version = var.addon_versions["coredns"]

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = { Name = "${var.cluster_name}-coredns" }

  depends_on = [module.nodegroup]
}
