locals {
  dns_options = var.enable_dns == "true"

  # Collect IDs of VPCs that match the Name tag but were NOT created by this
  # Terraform config.  Terraform-created VPCs carry ManagedBy = "Terraform"
  # via the provider default_tags block, so they are excluded here.
  # This prevents count from flipping 1 → 0 on a re-apply (which would
  # destroy the resource), while still skipping creation when a genuinely
  # pre-existing (externally managed) VPC already exists.
  external_vpc_ids = [
    for id, v in data.aws_vpc.by_name :
    id if lookup(v.tags, "ManagedBy", "") != "Terraform"
  ]

  vpc_exists = length(local.external_vpc_ids) > 0
  vpc_id     = local.vpc_exists ? local.external_vpc_ids[0]                              : aws_vpc.kr_vpc[0].id
  vpc_arn    = local.vpc_exists ? data.aws_vpc.by_name[local.external_vpc_ids[0]].arn   : aws_vpc.kr_vpc[0].arn
}

# ── Find VPCs whose Name tag matches the target name ─────────────────────────
data "aws_vpcs" "by_name" {
  filter {
    name   = "tag:Name"
    values = [var.tags["Name"]]
  }
}

# ── Fetch full details (including tags) for every matching VPC ────────────────
data "aws_vpc" "by_name" {
  for_each = toset(data.aws_vpcs.by_name.ids)
  id       = each.value
}

# ── Create only when no externally-managed VPC exists ────────────────────────
# count = 1  → Terraform-created VPC (ManagedBy=Terraform excluded above)
# count = 0  → pre-existing external VPC found; skip creation
resource "aws_vpc" "kr_vpc" {
  count = local.vpc_exists ? 0 : 1

  cidr_block           = var.cidr
  enable_dns_hostnames = local.dns_options
  enable_dns_support   = local.dns_options

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}