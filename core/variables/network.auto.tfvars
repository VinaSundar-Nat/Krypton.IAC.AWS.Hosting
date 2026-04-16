# =============================================================================
# core/variables/network.auto.tfvars — MASTER TEMPLATE
#
# REPLACE_* tokens are substituted by scripts/replace-vars.sh at runtime.
# Restored to this state by scripts/revert-master-vars.sh after terraform runs.
#
# Source:
#   environment/<ENV>/security/network.yaml  → VPC, AZs, NAT, tags
#   environment/<ENV>/zoning/*.yml           → subnet_zones map
#
# DO NOT edit REPLACE_* tokens — edit the source YAML files instead.
# =============================================================================

vpc_name       = "REPLACE_VPC_NAME"
vpc_cidr       = "REPLACE_VPC_CIDR"
vpc_enable_dns = REPLACE_VPC_ENABLE_DNS
vpc_tags       = REPLACE_VPC_TAGS

availability_zones = REPLACE_AVAILABILITY_ZONES

# Explicit subnet definitions — from environment/<ENV>/security/network.yaml component.subnets[]
subnets = REPLACE_SUBNETS

# Keyed by zone name — populated from environment/<ENV>/zoning/*.yml
subnet_zones = REPLACE_SUBNET_ZONES

# DHCP options — from network.yaml component.dhcp_options
# Includes: enabled, domain_name, domain_name_servers (list), provider
dhcp_options = REPLACE_DHCP_OPTIONS

nat_gateway_name   = "REPLACE_NAT_GATEWAY_NAME"
enable_nat_gateway = REPLACE_NAT_ENABLED
single_nat_gateway = REPLACE_NAT_SINGLE

internet_gateway_name    = "REPLACE_IGW_NAME"
internet_gateway_enabled = REPLACE_IGW_ENABLED

# Route tables — from network.yaml component.route_tables[]
route_tables = REPLACE_ROUTE_TABLES

private_ip_assignments = {}

common_tags = {
  environment  = "REPLACE_ENVIRONMENT"
  program      = "REPLACE_PROGRAM"
  organisation = "REPLACE_ORGANISATION"
  managed_by   = "terraform"
}
