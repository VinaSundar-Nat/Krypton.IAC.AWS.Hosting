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

vpc_name       = "kr-carevo-dev-vpc"
vpc_cidr       = "10.10.0.0/16"
vpc_enable_dns = true
vpc_tags       = {
  name = "kr-carevo-dev-vpc"
}

availability_zones = ["us-east-1a", "us-east-1b"]

# Explicit subnet definitions — from environment/<ENV>/security/network.yaml component.subnets[]
subnets = [
  { name = "kr-carevo-dev-public-subnet-ect", cidr = "10.10.1.0/24", type = "public", availability_zone = ["us-east-1a", "us-east-1b"] },
  { name = "kr-carevo-dev-private-subnet-rst", cidr = "10.10.2.0/24", type = "private", availability_zone = ["us-east-1a", "us-east-1b"] },
  { name = "kr-carevo-dev-private-subnet-ict", cidr = "10.10.3.0/24", type = "private", availability_zone = ["us-east-1a", "us-east-1b"] }
]

# Keyed by zone name — populated from environment/<ENV>/zoning/*.yml
subnet_zones = {
  cache = { cidr = "10.10.30.0/24", public = false }
  data = { cidr = "10.10.20.0/24", public = false }
  web = { cidr = "10.10.0.0/24", public = true }
  app = { cidr = "10.10.10.0/24", public = false }}

# DHCP options — from network.yaml component.dhcp_options
dhcp_options = { enabled = true, domain_name = "ecnt.dev.carevo.krypton.internal", domain_name_servers = ["AmazonProvidedDNS"], provider = "aws" }

nat_gateway_name   = "kr-carevo-dev-nat-gateway"
enable_nat_gateway = true
single_nat_gateway = true

internet_gateway_name    = "kr-carevo-dev-internet-gateway"
internet_gateway_enabled = true

# Route tables — from network.yaml component.route_tables[]
route_tables = [
  { name = "kr-carevo-dev-public-rt", type = "public", routes = [ { destination = "0.0.0.0/0", target = "kr-carevo-dev-internet-gateway" } ] },
  { name = "kr-carevo-dev-private-rt", type = "private", routes = [ { destination = "0.0.0.0/0", target = "kr-carevo-dev-nat-gateway" } ] }
]

private_ip_assignments = {}

common_tags = {
  environment  = "dev"
  program      = "carevo"
  organisation = "krypton"
  managed_by   = "terraform"
}
