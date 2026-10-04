variable "name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "max_image_count" {
  description = "Number of images to keep before older ones expire."
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Delete the repository on destroy even if it contains images."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
