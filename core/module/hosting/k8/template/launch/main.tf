# =============================================================================
# main.tf — EKS Launch Template Module
#
# Creates AWS launch templates for EKS nodegroups.
# One launch template per nodegroup definition.
# =============================================================================

locals {
  # Flatten nodegroups: combine cluster context with each nodegroup
  # Key format: "${cluster_name}__${nodegroup_name}" for uniqueness
  nodegroups_flat = merge([
    for cluster in var.eks_clusters :
    {
      for ng in cluster.nodegroups : "${cluster.name}__${ng.name}" => {
        cluster_name = cluster.name
        nodegroup    = ng
      }
    }
    if var.eks_enabled && lower(cluster.mode) == "managed"
  ]...)
}

# ── Resolve security group IDs for each nodegroup ─────────────────────────────
locals {
  nodegroup_security_group_ids = {
    for key, item in local.nodegroups_flat : key => concat(
      [
        for sg_name in item.nodegroup.template_parameters.security_groups :
        var.security_group_ids[sg_name]
        if contains(keys(var.security_group_ids), sg_name)
      ],
      contains(keys(var.cluster_security_group_ids), item.cluster_name) ? [
        var.cluster_security_group_ids[item.cluster_name]
      ] : []
    )
  }
}

# ── Create Launch Templates for each Nodegroup ─────────────────────────────────
resource "aws_launch_template" "kr_nodegroup_launch_template" {
  for_each = local.nodegroups_flat

  name_prefix = each.value.nodegroup.template_parameters.name_prefix
  description = each.value.nodegroup.template_parameters.description

  vpc_security_group_ids = local.nodegroup_security_group_ids[each.key]

  # Block device mapping for root volume
  dynamic "block_device_mappings" {
    for_each = [each.value.nodegroup.template_parameters.block_device_mappings]
    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        volume_size           = block_device_mappings.value.volume_size
        volume_type           = block_device_mappings.value.volume_type
        delete_on_termination = block_device_mappings.value.delete_on_termination
        encrypted             = block_device_mappings.value.encrypted
      }
    }
  }

  # Monitoring configuration
  monitoring {
    enabled = each.value.nodegroup.template_parameters.monitoring.enabled
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.common_tags,
      each.value.nodegroup.template_parameters.tags,
      {
        Name = each.value.nodegroup.template_parameters.name
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.common_tags,
      each.value.nodegroup.template_parameters.tags,
      {
        Name = each.value.nodegroup.template_parameters.name
      }
    )
  }

  lifecycle {
    create_before_destroy = false
    # create_before_destroy = try(each.value.nodegroup.template_parameters.lifecycle.create_before_destroy, false)
  }

  tags = merge(
    var.common_tags,
    {
      Name = each.value.nodegroup.template_parameters.name
    }
  )
}
