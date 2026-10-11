locals {
  name = "${var.name_prefix}-alb-controller"

  # The IRSA trust policy and the Helm values must agree on this identity.
  service_account_subject = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

################################################################################
# IAM policy: the official iam_policy.json for the pinned controller version.
# The file name carries the version, so bumping controller_version without
# adding the matching policy fails at plan time instead of drifting silently.
################################################################################

resource "aws_iam_policy" "this" {
  name        = local.name
  description = "AWS Load Balancer Controller v${var.controller_version} (official iam_policy.json)"
  policy      = file("${path.module}/iam-policy-v${var.controller_version}.json")

  tags = merge(var.tags, { Name = local.name })
}

################################################################################
# IRSA role: only the controller's service account, presenting a token issued
# by this cluster's OIDC provider for the STS audience, can assume it.
################################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:sub"
      values   = [local.service_account_subject]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

################################################################################
# Helm release
################################################################################

resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  namespace  = var.namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.controller_version

  # Wait until the deployment is available, so a broken install fails the apply.
  wait    = true
  timeout = 600

  values = [yamlencode({
    clusterName  = var.cluster_name
    replicaCount = var.replica_count

    # Passed explicitly: nodes use IMDS hop limit 1, so the pod cannot look
    # these up from instance metadata.
    region = var.region
    vpcId  = var.vpc_id

    serviceAccount = {
      create = true
      name   = var.service_account_name
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
      }
    }

    # Tags for every AWS resource the controller creates (ALBs, target groups,
    # security groups).
    defaultTags = var.aws_resource_tags

    # This webhook intercepts every Service creation with failurePolicy Fail.
    # We only use Ingress, and with one replica a controller restart would
    # block creating even ClusterIP Services, so it is turned off.
    enableServiceMutatorWebhook = false
  })]

  # The role must be able to call AWS before the pod starts reconciling.
  depends_on = [aws_iam_role_policy_attachment.this]
}
