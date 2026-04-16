# =============================================================================
# variables.tf — Route Table Module
#
# Accepts subnet details, route table configurations, and enables route
# table creation with subnet associations.
# =============================================================================

variable "vpc_id" {
  description = "VPC ID where route tables will be created."
  type        = string
}

variable "subnet_details" {
  description = <<-EOT
    List of subnet details from subnet module output.
    Each entry contains: subnet_id, name, cidr_block, type, az, vpc_id.
  EOT
  type = list(object({
    subnet_id   = string
    name        = string
    cidr_block  = string
    type        = string
    az          = string
    vpc_id      = string
  }))
  default = []
}

variable "route_tables" {
  description = <<-EOT
    List of route table definitions.
    Each entry specifies: name, type (public|private), and routes.
    Routes include destination CIDR and target (gateway name).
  EOT
  type = list(object({
    name   = string
    type   = string
    routes = list(object({
      destination = string
      target      = optional(string, "")
    }))
  }))
  default = []
}

variable "internet_gateway_id" {
  description = "Internet Gateway ID for public route table routes."
  type        = string
  default     = ""
}

variable "nat_gateway_id" {
  description = "NAT Gateway ID for private route table routes."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags applied to all route tables."
  type        = map(string)
  default     = {}
}

variable "enabled" {
  description = "Whether to create route table resources."
  type        = bool
  default     = true
}
