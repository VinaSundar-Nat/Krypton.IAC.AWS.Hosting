
# =============================================================================
# variables.tf — Subnet Module
#
# Accepts a list of subnet definitions and creates them with CIDR subnetting
# based on availability zone count. Validates existence before creation.
# =============================================================================

variable "vpc_id" {
  description = "VPC ID where subnets will be created."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC for subnetting calculation."
  type        = string
}

variable "region" {
  description = "AWS region for resource creation."
  type        = string
}

variable "subnets" {
  type = list(object({
    name              = string
    cidr              = string
    type              = string
    availability_zone = list(string)
  }))
  default = []
}

variable "common_tags" {
  description = "Common tags applied to all subnets."
  type        = map(string)
  default     = {}
}

variable "enabled" {
  description = "Whether to create subnet resources."
  type        = bool
  default     = true
}