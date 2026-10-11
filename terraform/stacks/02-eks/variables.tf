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
  description = "S3 bucket that holds Terraform state. Used to read stack 01-base outputs."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "dentsu-demo"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane and nodes."
  type        = string
  default     = "1.36"
}

variable "additional_admin_principal_arns" {
  description = "Extra IAM principals given cluster-admin, for example your IAM user for the EKS console. The Jenkins host role is always included."
  type        = list(string)
  default     = []
}

variable "node_ami_type" {
  description = "AMI family for the nodes."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_instance_types" {
  description = "Instance types for the nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum number of nodes."
  type        = number
  default     = 1
}

variable "node_desired_size" {
  description = "Desired number of nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes."
  type        = number
  default     = 1
}

variable "node_disk_size" {
  description = "Root volume size of each node in GiB."
  type        = number
  default     = 20
}

variable "addon_versions" {
  description = "EKS add-on versions. Defaults are the AWS default versions for Kubernetes 1.36 (aws eks describe-addon-versions)."
  type        = map(string)
  default = {
    "vpc-cni"    = "v1.22.4-eksbuild.3"
    "kube-proxy" = "v1.36.0-eksbuild.25"
    "coredns"    = "v1.14.6-eksbuild.4"
  }
}
