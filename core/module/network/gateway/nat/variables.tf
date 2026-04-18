# =============================================================================
# variables.tf — NAT Gateway Module
#
# Variable declarations for NAT gateway resources.
# =============================================================================

variable "enabled" {
  description = "Whether to create NAT gateway resources."
  type        = bool
  default     = true
}

variable "name" {
  description = "Base name for the NAT gateway (used as the Name tag)."
  type        = string
}

variable "single" {
  description = "When true, create a single NAT gateway shared across all AZs. When false, create one per AZ."
  type        = bool
  default     = false
}

variable "availability_zones" {
  description = "List of availability zones in which to create NAT gateways."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Map of AZ -> public subnet ID. NAT gateways are placed in public subnets."
  type        = map(string)
}

variable "vpc_id" {
  description = "VPC ID used when filtering existing NAT gateways."
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all NAT gateway resources."
  type        = map(string)
  default     = {}
}
