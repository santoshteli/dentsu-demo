data "aws_partition" "current" {}

################################################################################
# Cluster IAM role: lets the EKS control plane manage AWS resources
# (ENIs in our subnets, the cluster security group) on our behalf.
################################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, { Name = "${var.name}-eks-cluster" })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

################################################################################
# Cluster
################################################################################

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # Do not pre-install unmanaged vpc-cni, kube-proxy and CoreDNS. The stack
  # installs all three as EKS add-ons so Terraform owns their versions.
  # Changing this after creation replaces the cluster.
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids = var.subnet_ids

    # Private-only API: reachable from inside the VPC, not from the internet.
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  access_config {
    # Access entries only, no aws-auth ConfigMap.
    authentication_mode = "API"

    # Admin access is granted explicitly below, so it is visible in code.
    bootstrap_cluster_creator_admin_permissions = false
  }

  # Standard support only. Extended support costs six times as much per hour.
  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = merge(var.tags, { Name = var.name })

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# The private endpoint's ENIs use the cluster security group, so callers
# such as the Jenkins host need an explicit 443 rule into it.
resource "aws_vpc_security_group_ingress_rule" "api_access" {
  count = length(var.api_access_security_group_ids)

  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = var.api_access_security_group_ids[count.index]
  description                  = "Kubernetes API from ${var.api_access_security_group_ids[count.index]}"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = merge(var.tags, { Name = "${var.name}-api-from-${var.api_access_security_group_ids[count.index]}" })
}

################################################################################
# Cluster admins (access entries)
################################################################################

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(var.tags, { Name = "${var.name}-admin" })
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin[each.key].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

################################################################################
# OIDC provider, used by IRSA in stack 03-addons. AWS validates EKS issuers
# against its own trusted CAs, so no thumbprint is needed.
################################################################################

resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(var.tags, { Name = "${var.name}-oidc" })
}
