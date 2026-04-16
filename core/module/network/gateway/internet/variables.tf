# =============================================================================
# variables.tf — Internet Gateway Module
#
# Variable declarations for internet gateway resources.
# =============================================================================

variable "vpc_id" {
  description = "VPC ID where the internet gateway will be attached."
  type        = string
}

variable "tags" {
  description = "Tags to apply to the internet gateway."
  type        = map(string)
}

variable "enabled" {
  description = "Whether to create the internet gateway resource."
  type        = bool
  default     = true
}
