output "kr_vpc_dhcp_id" {
  value = var.enabled ? aws_vpc_dhcp_options.kr_dhcp_options[0].id : null
}

