variable "name" {
  description = "Prefix for the node group, node IAM role and launch template."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster the node group joins."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the nodes. Keep equal to the control plane."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets the nodes are launched in."
  type        = list(string)
}

variable "ami_type" {
  description = "EKS-optimized AMI family."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "instance_types" {
  description = "Instance types for the nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "min_size" {
  description = "Minimum number of nodes."
  type        = number
  default     = 1
}

variable "desired_size" {
  description = "Desired number of nodes."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes."
  type        = number
  default     = 1
}

variable "disk_size" {
  description = "Root volume size of each node in GiB."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Extra tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
