variable "name" {
  description = "Name prefix for all VPC resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One public subnet CIDR per AZ, in the same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must have one entry per AZ."
  }
}

variable "private_subnet_cidrs" {
  description = "One private subnet CIDR per AZ, in the same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs must have one entry per AZ."
  }
}

variable "tags" {
  description = "Extra tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
