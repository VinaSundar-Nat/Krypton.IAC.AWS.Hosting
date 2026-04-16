locals {
  dhcp_exists = length(data.aws_dhcp_options.existing.ids) > 0
  region      = var.region
  dhcp_options_id = local.dhcp_exists ? data.aws_dhcp_options.existing.ids[0] : aws_vpc_dhcp_options.kr_dhcp_options[0].id
}

# ── Check for an existing DHCP options set by Name tag (returns empty list — never errors) ─
data "aws_dhcp_options" "existing" {
  filter {
    name   = "tag:Name"
    values = [var.tags["Name"]]
  }
}

# ── Fetch full details when a matching VPC was found ──────────────────────────
data "aws_vpc_dhcp_options" "kr_dhcp_options" {
  count = !local.dhcp_exists && var.enabled ? 1 : 0

  region = var.region

  domain_name                       = var.domain_name
  domain_name_servers               = var.domain_name_servers

  tags = merge(
    var.tags,
    {
      "CreatedOn" = var.created_on
    }
  )
}

resource "aws_vpc_dhcp_options_association" "kr_dhcp_options_link" {
  count = !local.dhcp_exists && var.enabled ? 1 : 0

  region = var.region

  vpc_id          = var.vpc_id
  dhcp_options_id = local.dhcp_options_id
}