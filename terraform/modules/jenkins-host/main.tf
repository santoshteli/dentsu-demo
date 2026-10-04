data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Latest AL2023 AMI, resolved through the public SSM parameter.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name       = "${var.name_prefix}-jenkins"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
}

################################################################################
# Security group: no inbound rules at all. Access is through SSM Session
# Manager, which only needs outbound HTTPS from the host.
################################################################################

resource "aws_security_group" "this" {
  name        = local.name
  description = "Jenkins host: no inbound, all outbound"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound: SSM, package repos, ECR, EKS API"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

################################################################################
# IAM role and instance profile
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

resource "aws_iam_role" "this" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

resource "aws_iam_instance_profile" "this" {
  name = local.name
  role = aws_iam_role.this.name

  tags = var.tags
}

# Lets Session Manager manage the host, so no SSH key or open port is needed.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ECR push and pull, scoped to the one application repository.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# What Terraform needs to run stacks 02-eks and 03-addons from this host.
# IAM writes are limited to names that start with the project prefix.
data "aws_iam_policy_document" "terraform" {
  statement {
    sid = "StateBucketList"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}"]
  }

  statement {
    sid = "StateObjects"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}/*"]
  }

  statement {
    sid       = "Eks"
    actions   = ["eks:*"]
    resources = ["*"]
  }

  statement {
    sid = "Ec2ReadAndSecurityGroups"
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteTags",
      "ec2:Describe*",
      "ec2:GetLaunchTemplateData",
      "ec2:ModifySecurityGroupRules",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
    ]
    resources = ["*"]
  }

  statement {
    sid = "IamProjectRoles"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${var.name_prefix}-*"]
  }

  statement {
    sid = "IamProjectPolicies"
    actions = [
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:policy/${var.name_prefix}-*"]
  }

  statement {
    sid = "IamReadAwsManagedPolicies"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
    ]
    resources = ["arn:${local.partition}:iam::aws:policy/*"]
  }

  statement {
    sid = "IamOidcProvider"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/oidc.eks.${local.region}.amazonaws.com/*"]
  }

  statement {
    sid       = "IamServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "autoscaling.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "IamReadServiceLinkedRoles"
    actions   = ["iam:GetRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]
  }

  statement {
    sid       = "EksPublicParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/aws/service/eks/*"]
  }

  statement {
    sid = "EksControlPlaneLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:ListTagsForResource",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/eks/${var.name_prefix}-*"]
  }

  statement {
    sid       = "LogsDescribe"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # The host's own role matches the project prefix, so explicitly stop it
  # from editing itself and widening its own permissions.
  statement {
    sid       = "DenySelfModification"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = [aws_iam_role.this.arn]
  }
}

resource "aws_iam_role_policy" "terraform" {
  name   = "terraform-stacks-02-03"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.terraform.json
}

################################################################################
# EC2 instance
################################################################################

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    kubectl_version   = var.kubectl_version
    helm_version      = var.helm_version
    terraform_version = var.terraform_version
  })
  user_data_replace_on_change = true

  # IMDSv2 only. A hop limit of 1 stops containers that Jenkins builds
  # from reading the host's instance profile credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = local.name })

  lifecycle {
    # A newer AL2023 AMI should not replace a running Jenkins host.
    ignore_changes = [ami]
  }

  depends_on = [aws_iam_role_policy_attachment.ssm]
}
