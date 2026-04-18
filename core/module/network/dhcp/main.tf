locals {
  region = var.region
}

# ── DHCP options set – Terraform state guarantees idempotency. ────────────────
# Data-source tag lookups hard-fail at plan time when nothing matches, so the
# create-or-reuse pattern must be handled via 'terraform import' for resources
# that were provisioned outside this module.
resource "aws_vpc_dhcp_options" "kr_dhcp_options" {
  count = var.enabled ? 1 : 0

  domain_name         = var.domain_name
  domain_name_servers = var.domain_name_servers

  tags = merge(
    var.tags,
    {
      "CreatedOn" = var.created_on
    }
  )
}

resource "aws_vpc_dhcp_options_association" "kr_dhcp_options_link" {
  count = var.enabled ? 1 : 0

  vpc_id          = var.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.kr_dhcp_options[0].id
}