variable "name" {
  description = "Cluster name. Also the prefix for the cluster IAM role."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane, for example 1.36."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs. At least two AZs."
  type        = list(string)
}

variable "api_access_security_group_ids" {
  description = "Security groups allowed to reach the private API endpoint on 443."
  type        = list(string)
  default     = []
}

variable "admin_principal_arns" {
  description = "IAM role or user ARNs that get cluster-admin through an access entry."
  type        = list(string)
}

variable "tags" {
  description = "Extra tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
