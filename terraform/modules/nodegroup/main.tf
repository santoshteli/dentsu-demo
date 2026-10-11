data "aws_partition" "current" {}

# Provider default_tags do not reach tag_specifications, so read them here
# and copy them onto the instances, volumes and ENIs the node group launches.
data "aws_default_tags" "current" {}

locals {
  node_name = "${var.name}-eks-node"
  node_tags = merge(data.aws_default_tags.current.tags, var.tags, { Name = local.node_name })
}

################################################################################
# Node IAM role
################################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = local.node_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, { Name = local.node_name })
}

# WorkerNode: join the cluster. CNI: the vpc-cni plugin assigns pod IPs.
# PullOnly: pull images from ECR.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryPullOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

################################################################################
# Launch template: tags, encrypted disk and IMDSv2 for the nodes. No AMI ID,
# so EKS still picks the AMI from ami_type and merges its bootstrap user data.
################################################################################

resource "aws_launch_template" "node" {
  name                   = local.node_name
  description            = "Managed node group ${var.name}-ng"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 only. Hop limit 1 stops pods from reading the node role's
  # credentials; pods that need AWS access use IRSA instead.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.node_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.node_tags, { Name = "${local.node_name}-root" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.node_tags
  }

  tags = merge(var.tags, { Name = local.node_name })
}

################################################################################
# Managed node group
################################################################################

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  version         = var.kubernetes_version

  ami_type       = var.ami_type
  capacity_type  = var.capacity_type
  instance_types = var.instance_types

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    min_size     = var.min_size
    desired_size = var.desired_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(var.tags, { Name = "${var.name}-ng" })

  # The role must have its policies before nodes boot, or they cannot join.
  depends_on = [aws_iam_role_policy_attachment.node]
}
