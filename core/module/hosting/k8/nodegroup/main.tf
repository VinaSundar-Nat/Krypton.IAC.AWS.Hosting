# =============================================================================
# main.tf — EKS NodeGroup Module
#
# Creates AWS EKS nodegroups with launch template integration.
# One nodegroup per nodegroup definition with launch template reference.
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

# ── Resolve subnet IDs by matching nodegroup subnet names ──────────────────────
locals {
  nodegroup_subnet_ids = {
    for key, item in local.nodegroups_flat : key => [
      for subnet_name in item.nodegroup.subnets : [
        for subnet_detail in var.subnet_details :
        subnet_detail.subnet_id
        if subnet_detail.name == subnet_name
      ]
    ]
  }
}

# ── Create EKS NodeGroups ──────────────────────────────────────────────────────
resource "aws_eks_node_group" "kr_nodegroup" {
  for_each = local.nodegroups_flat

  cluster_name    = each.value.cluster_name
  node_group_name = each.value.nodegroup.name
  node_role_arn   = var.nodegroup_role_arns[each.value.nodegroup.role]

  subnet_ids = flatten(local.nodegroup_subnet_ids[each.key])

  instance_types = each.value.nodegroup.machine.instance_types
  ami_type       = each.value.nodegroup.machine.ami_type
  capacity_type  = each.value.nodegroup.machine.capacity_type

  scaling_config {
    desired_size = each.value.nodegroup.scaling_config.desired_size
    max_size     = each.value.nodegroup.scaling_config.max_size
    min_size     = each.value.nodegroup.scaling_config.min_size
  }

  launch_template {
    id      = var.launch_template_ids[each.key]
    version = tostring(var.launch_template_latest_versions[each.key])
  }

  tags = merge(
    var.common_tags,
    each.value.nodegroup.template_parameters.tags,
    {
      Name = each.value.nodegroup.name
    }
  )

  depends_on = []
}
