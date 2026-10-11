variable "name_prefix" {
  description = "Prefix for the IAM policy and role (<prefix>-alb-controller)."
  type        = string
}

variable "controller_version" {
  description = "Controller and Helm chart version, without the leading v. A matching iam-policy-v<version>.json must exist in this module."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster the controller manages load balancers for."
  type        = string
}

variable "region" {
  description = "AWS region of the cluster."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the cluster."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider."
  type        = string
}

variable "oidc_issuer" {
  description = "Cluster OIDC issuer without https://, used as the prefix of the IRSA condition keys."
  type        = string
}

variable "namespace" {
  description = "Namespace for the controller."
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Service account name. The IRSA role trusts only this account."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "replica_count" {
  description = "Number of controller pods."
  type        = number
  default     = 1
}

variable "aws_resource_tags" {
  description = "Tags the controller puts on the AWS resources it creates."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Extra tags applied to the IAM resources in this module."
  type        = map(string)
  default     = {}
}
