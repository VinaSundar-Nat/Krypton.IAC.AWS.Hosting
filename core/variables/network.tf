# =============================================================================
# variables/network.tf
#
# Variable declarations for all network resources:
#   VPC, subnets (keyed by zone), NAT gateway, route tables, private IPs, tags.
#
# Values are generated from environment YAML by scripts/replace-vars.sh
# into core/variables/network.auto.tfvars, which runner.sh passes via -var-file.
#
# Symlinked from core/network.tf so Terraform's root module picks it up.
# =============================================================================



# ── VPC ───────────────────────────────────────────────────────────────────────
variable "vpc_name" {
  description = "VPC name — derived by replace-vars.sh from network.yaml component.name."
  type        = string
}

variable "vpc_cidr" {
  description = "Primary CIDR block for the VPC."
  type        = string
}

# ── Availability Zones ────────────────────────────────────────────────────────
variable "availability_zones" {
  description = "Ordered list of AZs to spread subnets across — derived by replace-vars.sh from network.yaml component.availability_zone."
  type        = list(string)
}

variable "vpc_enable_dns" {
  description = "VPC enable DCHP DNS settings — derived by replace-vars.sh from network.yaml component.enabledns."
  type        = string
}

variable "vpc_tags" {
  description = "VPC tags — derived by replace-vars.sh from network.yaml component.tags."
  type        = map(string)
}

# ── Subnet zones ──────────────────────────────────────────────────────────────
# Keyed by zone label (web | app | data | cache).
# Values are derived from environment/dev/zoning/*.yml by replace-vars.sh.
variable "subnet_zones" {
  description = <<-EOT
    Map of subnet zone definitions, one entry per zoning YAML file.
    Keys match the zone names (web, app, data, cache).
    public = true  → placed in public subnet with IGW route.
    public = false → placed in private subnet, routed through NAT.
  EOT
  type = map(object({
    cidr   = string
    public = bool
  }))
}

# ── Subnets ───────────────────────────────────────────────────────────────────
# Explicit subnet definitions sourced from network.yaml component.subnets[].
# Each entry carries a logical name, CIDR, type (public|private), and list of AZs.
variable "subnets" {
  description = <<-EOT
    List of subnet definitions sourced from network.yaml component.subnets[].
    Each subnet specifies availability zones (list of strings) from component.availability_zone.
    type = public  → associated with IGW route table.
    type = private → associated with NAT gateway route table.
  EOT
  type = list(object({
    name              = string
    cidr              = string
    type              = string
    availability_zone = list(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for subnet in var.subnets :
      contains(["public", "private"], subnet.type)
    ])
    error_message = "Subnet type must be either 'public' or 'private'."
  }
}

# ── DHCP Options ──────────────────────────────────────────────────────────────
variable "dhcp_options" {
  description = "Custom DHCP options set for the VPC. Set enabled = false to use AWS defaults."
  type = object({
    enabled                = bool
    domain_name            = string
    domain_name_servers    = list(string)
    provider               = string
  })
  default = {
    enabled             = false
    domain_name         = ""
    domain_name_servers = ["AmazonProvidedDNS"]
    provider            = "aws"
  }
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────
variable "nat_gateway_name" {
  description = "Name tag for the NAT gateway resource."
  type        = string
  default     = ""
}

variable "enable_nat_gateway" {
  description = "Provision a NAT gateway for private subnet egress."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway (cost-saving for non-prod). False = one per AZ."
  type        = bool
  default     = false
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
variable "internet_gateway_name" {
  description = "Name tag for the internet gateway resource."
  type        = string
  default     = ""
}

variable "internet_gateway_enabled" {
  description = "Attach an internet gateway to the VPC. Set false for fully private VPCs."
  type        = bool
  default     = true
}

# ── Route Tables ──────────────────────────────────────────────────────────────
# Sourced from network.yaml component.route_tables[].
variable "route_tables" {
  description = <<-EOT
    List of route table definitions sourced from network.yaml component.route_tables[].
    Each entry carries: name, type (public|private), and routes (with destination CIDR and target).
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

# ── Private IP assignments ────────────────────────────────────────────────────
# Map of logical resource name → fixed private IP within the VPC CIDR.
# Example: { "bastion" = "10.10.10.5" }
variable "private_ip_assignments" {
  description = "Optional fixed private IP addresses keyed by resource name."
  type        = map(string)
  default     = {}
}

# ── Common tags ───────────────────────────────────────────────────────────────
variable "common_tags" {
  description = "Tags applied to every network resource. Merged with resource-specific tags."
  type        = map(string)
  default     = {}
}
