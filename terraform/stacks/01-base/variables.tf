variable "project" {
  description = "Project name, used as the prefix for every resource name."
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
  description = "S3 bucket that holds Terraform state. Must match backend.hcl."
  type        = string

  validation {
    condition     = !strcontains(var.state_bucket_name, "REPLACE")
    error_message = "Set state_bucket_name in terraform.tfvars to your real state bucket."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to use."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per AZ. Sized /20 because the VPC CNI gives every pod a VPC IP."
  type        = list(string)
  default     = ["10.0.16.0/20", "10.0.32.0/20"]
}

variable "jenkins_instance_type" {
  description = "Instance type for the Jenkins host."
  type        = string
  default     = "t3.medium"
}

variable "enable_jenkins_alb" {
  description = "Put an internet-facing ALB in front of Jenkins for browser-only access. Costs about $0.03/hr while it exists."
  type        = bool
  default     = true
}

variable "jenkins_alb_allowed_cidrs" {
  description = "Client CIDRs allowed through the Jenkins ALB. Keep empty in git; add your IP in the console (Source: My IP) when needed."
  type        = list(string)
  default     = []
}

variable "kubectl_version" {
  description = "kubectl version for the Jenkins host. Keep within one minor version of the cluster."
  type        = string
  default     = "1.36.5"
}

variable "helm_version" {
  description = "Helm CLI version for the Jenkins host."
  type        = string
  default     = "3.22.0"
}

variable "terraform_version" {
  description = "Terraform version for the Jenkins host. Keep it equal to the laptop version."
  type        = string
  default     = "1.16.4"
}
