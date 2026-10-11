variable "project" {
  description = "Project name, used as the prefix for resource names."
  type        = string
  default     = "dentsu-demo"
}

variable "environment" {
  description = "Value of the Env tag on every resource."
  type        = string
  default     = "dentsu-demo"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket_name" {
  description = "S3 bucket that holds Terraform state. Used to read stacks 01-base and 02-eks."
  type        = string
}

variable "alb_controller_version" {
  description = "AWS Load Balancer Controller version (Helm chart version, same number). The module must contain iam-policy-v<version>.json."
  type        = string
  default     = "3.6.0"
}
