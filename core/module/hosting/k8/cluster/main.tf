# =============================================================================
# main.tf — EKS Cluster Module
#
# Creates AWS EKS clusters with managed mode validation.
# Only processes clusters with mode = "managed".
# =============================================================================

locals {
  # Filter enabled clusters with managed mode
  managed_clusters = {
    for cluster in var.eks_clusters :
    cluster.name => cluster
    if var.eks_enabled && lower(cluster.mode) == "managed"
  }
}

# ── Resolve subnet IDs by matching subnet name from subnet_details ──────────────
locals {
  cluster_subnet_ids = {
    for cluster_name, cluster in local.managed_clusters : cluster_name => [
      for subnet_name in cluster.subnets : [
        for subnet_detail in var.subnet_details :
        subnet_detail.subnet_id
        if subnet_detail.name == subnet_name
      ]
    ]
  }
}

# ── Resolve security group IDs by name ──────────────────────────────────────────
locals {
  cluster_security_group_ids = {
    for cluster_name, cluster in local.managed_clusters : cluster_name => [
      for sg_name in cluster.security_groups :
      var.security_group_ids[sg_name]
      if contains(keys(var.security_group_ids), sg_name)
    ]
  }
}

# ── Create EKS Clusters ────────────────────────────────────────────────────────
resource "aws_eks_cluster" "kr_cluster" {
  for_each = local.managed_clusters

  name     = each.value.name
  version  = each.value.version
  role_arn = var.cluster_role_arns[each.value.role]

  vpc_config {
    subnet_ids              = flatten(local.cluster_subnet_ids[each.key])
    security_group_ids      = local.cluster_security_group_ids[each.key]
    endpoint_public_access  = each.value.endpoint_public_access
    endpoint_private_access = each.value.endpoint_private_access
  }

  tags = merge(
    var.common_tags,
    {
      Name = each.value.name
    }
  )

  depends_on = []
}
