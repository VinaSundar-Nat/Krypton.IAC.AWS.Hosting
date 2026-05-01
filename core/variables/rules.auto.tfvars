# =============================================================================
# core/variables/rules.auto.tfvars — MASTER TEMPLATE
#
# REPLACE_* tokens are substituted by scripts/replace-vars.sh at runtime.
# Restored to this state by scripts/revert-master-vars.sh after terraform runs.
#
# Sources:
#   environment/<ENV>/platform/rules.yml  → SG zones, links, rules, and NACL rules
#
# DO NOT edit REPLACE_* tokens — edit the source YAML files instead.
# =============================================================================

security_groups_zone = [
    { name = "kr-carevo-dev-app-rst-sg", id = "kr-app-rst", enabled = true, description = "Restricted Security group for carevo dev environment - No external access, only from within VPC and private subnets" },
    { name = "kr-carevo-dev-web-ect-sg", id = "kr-web-ect", enabled = true, description = "External Security group for carevo dev environment - Allows HTTP/HTTPS from VPC and app port from private subnets" },
    { name = "kr-carevo-dev-app-ict-sg", id = "kr-app-ict", enabled = true, description = "Internal Security group for carevo dev environment - Allows controlled internal access and from VPC and private subnets" }
  ]

security_group_rule_link = [
    { source = "kr-web-ect", target = "", rules = {
      in001 = { cidr_blocks = "0.0.0.0/0" },
      in002 = { cidr_blocks = "0.0.0.0/0" }
    }, description = "Allow HTTP/HTTPS internet to web SG" },
    { source = "kr-web-ect", target = "kr-app-ict", rules = {
      eg003 = { cidr_blocks = "" }
    }, description = "Allow internal app port from web SG to internal SG" },
    { source = "kr-app-ict", target = "kr-web-ect", rules = {
      in003 = { cidr_blocks = "" }
    }, description = "Allow internal app port from web SG to internal SG" },
    { source = "kr-app-ict", target = "kr-app-rst", rules = {
      eg003 = { cidr_blocks = "" }
    }, description = "Allow app port from internal SG to app SG" },
    { source = "kr-app-rst", target = "kr-app-ict", rules = {
      in003 = { cidr_blocks = "" }
    }, description = "Allow app port from internal SG to restricted app SG" },
    { source = "kr-app-rst", target = "", rules = {
      eg001 = { cidr_blocks = "0.0.0.0/0" }
    }, description = "Allow https port from restricted SG to services" },
    { source = "kr-app-ict", target = "", rules = {
      eg001 = { cidr_blocks = "0.0.0.0/0" }
    }, description = "Allow https port from internal SG to services" }
  ]

security_group_rules = [
    { id = "in001", description = "HTTPS ingress", protocol = "tcp", from_port = 443, to_port = 443, type = "ingress" },
    { id = "eg001", description = "HTTPS egress", protocol = "tcp", from_port = 443, to_port = 443, type = "egress" },
    { id = "in002", description = "HTTP ingress", protocol = "tcp", from_port = 80, to_port = 80, type = "ingress" },
    { id = "eg002", description = "HTTP egress", protocol = "tcp", from_port = 80, to_port = 80, type = "egress" },
    { id = "in003", description = "App port ingress", protocol = "tcp", from_port = 8080, to_port = 8080, type = "ingress" },
    { id = "eg003", description = "App port egress", protocol = "tcp", from_port = 8080, to_port = 8080, type = "egress" },
    { id = "eg004", description = "Allow all outbound", protocol = "-1", from_port = 0, to_port = 0, type = "egress" }
  ]

nacl_zone = [
    { name = "kr-carevo-dev-rst-nacl", id = "kr-rst-nacl", enabled = true, description = "NACL for carevo dev environment - Restrictive private rules for app subnets", subnets = ["kr-carevo-dev-rst-nacl"] },
    { name = "kr-carevo-dev-ect-nacl", id = "kr-ect-nacl", enabled = true, description = "NACL for carevo dev environment - Moderate public rules for web subnets", subnets = ["kr-carevo-dev-ect-nacl"] },
    { name = "kr-carevo-dev-ict-nacl", id = "kr-ict-nacl", enabled = true, description = "NACL for carevo dev environment - Moderate private rules for internal subnets", subnets = ["kr-carevo-dev-ict-nacl"] }
  ]

nacl_rule_link = [
    { nacl = "kr-ect-nacl", rules = [
      { "in001" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "in002" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "in006" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "eg003" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "eg005" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } }
    ] },
    { nacl = "kr-ict-nacl", rules = [
      { "in005" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "in001" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "in006" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "eg003" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "eg005" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } }
    ] },
    { nacl = "kr-rst-nacl", rules = [
      { "in005" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "in001" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "in006" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "eg003" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } },
      { "eg005" = { rule_number = null, description = "null", cidr_block = "null", subnet = "null", action = "null" } }
    ] }
  ]

nacl_rules = [
    { id = "in001", description = "HTTPS ingress", protocol = "tcp", from_port = 443, to_port = 443, type = "ingress" },
    { id = "in002", description = "HTTP ingress", protocol = "tcp", from_port = 80, to_port = 80, type = "ingress" },
    { id = "in003", description = "Ephemeral port request traffic", protocol = "tcp", from_port = 1024, to_port = 65535, type = "ingress" },
    { id = "in005", description = "App port ingress", protocol = "tcp", from_port = 8080, to_port = 8080, type = "ingress" },
    { id = "in006", description = "Default deny all ingress", protocol = "-1", from_port = 0, to_port = 0, type = "ingress" },
    { id = "eg001", description = "HTTPS egress", protocol = "tcp", from_port = 443, to_port = 443, type = "egress" },
    { id = "eg002", description = "HTTP egress", protocol = "tcp", from_port = 80, to_port = 80, type = "egress" },
    { id = "eg003", description = "Ephemeral port response traffic", protocol = "tcp", from_port = 1024, to_port = 65535, type = "egress" },
    { id = "eg005", description = "App port egress", protocol = "tcp", from_port = 8080, to_port = 8080, type = "egress" }
  ]
