locals {
  dns_options = var.enable_dns == "true"
  vpc_exists  = length(data.aws_vpcs.existing.ids) > 0
  vpc_id      = local.vpc_exists ? data.aws_vpcs.existing.ids[0]  : aws_vpc.kr_carevo_vpc[0].id
  vpc_arn     = local.vpc_exists ? data.aws_vpc.existing[0].arn   : aws_vpc.kr_carevo_vpc[0].arn
}

# ── Check for an existing VPC by Name tag (returns empty list — never errors) ─
data "aws_vpcs" "existing" {
  filter {
    name   = "tag:Name"
    values = [var.tags["Name"]]
  }
}

# ── Fetch full details when a matching VPC was found ──────────────────────────
data "aws_vpc" "existing" {
  count = local.vpc_exists ? 1 : 0
  id    = data.aws_vpcs.existing.ids[0]
}

# ── Create only when no matching VPC exists ───────────────────────────────────
resource "aws_vpc" "kr_carevo_vpc" {
  count = local.vpc_exists ? 0 : 1

  cidr_block           = var.cidr
  enable_dns_hostnames = local.dns_options
  enable_dns_support   = local.dns_options

  tags = var.tags
}