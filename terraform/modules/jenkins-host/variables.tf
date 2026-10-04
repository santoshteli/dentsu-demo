variable "name_prefix" {
  description = "Project prefix. The host is named <prefix>-jenkins, and IAM writes from the host are limited to names that start with <prefix>-."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the host in."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the host."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the host."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root volume size in GiB. Docker images and the Jenkins workspace live here."
  type        = number
  default     = 30
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the host may push to."
  type        = string
}

variable "state_bucket_name" {
  description = "S3 bucket that holds Terraform state for all stacks."
  type        = string
}

variable "kubectl_version" {
  description = "kubectl version to install, without the leading v."
  type        = string
}

variable "helm_version" {
  description = "Helm version to install, without the leading v."
  type        = string
}

variable "terraform_version" {
  description = "Terraform version to install."
  type        = string
}

variable "tags" {
  description = "Extra tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
