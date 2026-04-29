# =============================================================================
# main.tf
#
# AWS Provider auth is toggled by the `auth_mode` variable:
#
#   auth_mode = "gha"   → assume_role_with_web_identity
#                          GitHub Actions writes an OIDC token to
#                          `web_identity_token_file`; Terraform exchanges it
#                          for STS credentials directly using the GHA role.
#
#   auth_mode = "local" → Named AWS CLI profile (`aws_profile`) that uses
#                          credential_process = aws_signing_helper ...
#                          runner.sh writes this profile before terraform runs.
#                          aws_signing_helper exchanges the X.509 cert/key for
#                          temporary STS credentials via IAM Roles Anywhere.
#
# Switch modes by exporting TF_VAR_auth_mode=gha|local before terraform init.
# =============================================================================

locals {
  is_gha   = var.auth_mode == "gha"
  is_local = var.auth_mode == "local"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Program     = var.program
      Organization = var.organisation
      email       = "vinasundar.aws@gmail.com"
      ManagedBy   = "Terraform"
    }
  }

  # ── Local / IAM Roles Anywhere ─────────────────────────────────────────────
  # When auth_mode = "local", the named profile contains:
  #   credential_process = aws_signing_helper credential-process \
  #     --certificate   <cert.pem> \
  #     --private-key   <key.pem>  \
  #     --trust-anchor-arn <arn>   \
  #     --profile-arn      <arn>   \
  #     --role-arn         <arn>
  # runner.sh writes this profile before invoking terraform.
  profile = local.is_local ? var.aws_profile : null

  # ── GitHub Actions OIDC ────────────────────────────────────────────────────
  # When auth_mode = "gha", the GHA workflow must:
  #   1. Set `permissions: id-token: write` on the job.
  #   2. Write the OIDC token to web_identity_token_file:
  #        curl -sH "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  #          "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" \
  #          | jq -r .value > /tmp/web-identity-token
  #   3. Export TF_VAR_auth_mode=gha and TF_VAR_gha_role_arn=<arn>.
  dynamic "assume_role_with_web_identity" {
    for_each = local.is_gha ? [1] : []
    content {
      role_arn                = var.gha_role_arn
      web_identity_token_file = var.web_identity_token_file
      session_name            = "github-actions-terraform"
    }
  }
}

# =============================================================================
# VPC Module – creates or references existing VPC
# =============================================================================
module "deploy-kr-vpc" {
  source     = "./module/network/vpc"
  cidr       = var.vpc_cidr
  enable_dns = var.vpc_enable_dns
  tags = merge(
    var.vpc_tags,
    {
      Name = var.vpc_tags["name"]
    }
  )
}

# =============================================================================
# DHCP Options Module – creates or references existing DHCP options set
# =============================================================================
module "deploy-kr-dhcp-options" {
  source = "./module/network/dhcp"

  enabled             = var.dhcp_options.enabled
  domain_name         = var.dhcp_options.domain_name
  domain_name_servers = var.dhcp_options.domain_name_servers
  vpc_id              = module.deploy-kr-vpc.kr_vpc_id
  region              = var.aws_region
  created_on          = formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())

  tags = {
    Name     = var.vpc_name
    Provider = var.dhcp_options.provider
  }
}

# =============================================================================
# Subnet Module – creates subnets with CIDR subnetting and AZ distribution
# =============================================================================
module "deploy-kr-subnets" {
  source = "./module/network/subnet"

  vpc_id   = module.deploy-kr-vpc.kr_vpc_id
  vpc_cidr = var.vpc_cidr
  region   = var.aws_region
  subnets  = var.subnets
  enabled  = length(var.subnets) > 0 ? true : false

  common_tags = {
    VPC          = var.vpc_name
    Organization = var.organisation
    Program      = var.program
    Environment  = var.environment
  }

  depends_on = [module.deploy-kr-vpc]
}

# =============================================================================
# Internet Gateway Module – creates or references existing IGW
# =============================================================================
module "deploy-kr-internet-gateway" {
  source = "./module/network/gateway/internet"

  vpc_id  = module.deploy-kr-vpc.kr_vpc_id
  enabled = var.internet_gateway_enabled

  tags = {
    Name = var.internet_gateway_name
  }

  depends_on = [module.deploy-kr-vpc]
}



# =============================================================================
# NAT Gateway Module – creates or references existing NAT gateway(s) by Name tag
# =============================================================================
module "deploy-kr-nat-gateway" {
  source = "./module/network/gateway/nat"

  enabled            = var.enable_nat_gateway
  name               = var.nat_gateway_name
  single             = var.single_nat_gateway
  availability_zones = var.availability_zones
  vpc_id             = module.deploy-kr-vpc.kr_vpc_id

  # Build AZ → public-subnet-ID map from the subnet module's subnet_details output.
  # Where multiple public subnets share the same AZ, the first one wins (NAT GW
  # only needs one public subnet per AZ; using try/coalesce avoids key collisions).
  public_subnet_ids = {
    for az in distinct([
      for s in module.deploy-kr-subnets.subnet_details : s.az
      if s.type == "public"
    ]) :
    az => [
      for s in module.deploy-kr-subnets.subnet_details :
      s.subnet_id
      if s.type == "public" && s.az == az
    ][0]
  }

  tags = {
    Name        = var.nat_gateway_name
    Environment = var.environment
    Program     = var.program
    ManagedBy   = "terraform"
  }

  depends_on = [
    module.deploy-kr-subnets,
    module.deploy-kr-internet-gateway,
  ]
}

# =============================================================================
# Route Table Module – creates or references existing route tables by Name tag
# =============================================================================
module "deploy-kr-route-tables" {
  source = "./module/network/route-table"

  vpc_id              = module.deploy-kr-vpc.kr_vpc_id
  route_tables        = var.route_tables
  subnet_details      = module.deploy-kr-subnets.subnet_details
  internet_gateway_id = module.deploy-kr-internet-gateway.igw_id
  nat_gateway_id      = module.deploy-kr-nat-gateway.nat_gateway_id
  enabled             = length(var.route_tables) > 0

  tags = {
    Environment  = var.environment
    Program      = var.program
    Organisation = var.organisation
    ManagedBy    = "terraform"
  }

  depends_on = [
    module.deploy-kr-subnets,
    module.deploy-kr-internet-gateway,
    module.deploy-kr-nat-gateway,
  ]
}

# =============================================================================
# Security Group Module – creates security groups and ingress/egress rules
# from zone definitions and rule-link declarations in rules.auto.tfvars.
# =============================================================================
module "deploy-kr-security-groups" {
  source = "./module/rules/sg"

  vpc_id                   = module.deploy-kr-vpc.kr_vpc_id
  security_groups_zone     = var.security_groups_zone
  security_group_rule_link = var.security_group_rule_link
  security_group_rules     = var.security_group_rules

  common_tags = {
    Team         = "Carevo DevOps Network Security"
  }

  depends_on = [module.deploy-kr-vpc]
}
