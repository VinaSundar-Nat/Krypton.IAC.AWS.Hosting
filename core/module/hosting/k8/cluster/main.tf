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

  access_config {
    authentication_mode = "API"
  }

  tags = merge(
    var.common_tags,
    {
      Name = each.value.name
    }
  )

  depends_on = []
}

# =============================================================================
# Step 2: EKS Access Entries
# Grant IAM principals Kubernetes API access using the EKS access entry API.
# One aws_eks_access_entry + aws_eks_access_policy_association per entry.
# Key: "${cluster_name}__${principal_arn}" for uniqueness.
# =============================================================================
locals {
  cluster_access_map = {
    for entry in var.cluster_access :
    "${entry.cluster_name}__${entry.principal_arn}" => entry
  }
}

resource "aws_eks_access_entry" "kr_cluster_access" {
  for_each = local.cluster_access_map

  cluster_name  = each.value.cluster_name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  tags = merge(
    var.common_tags,
    {
      Description = each.value.description
    }
  )

  depends_on = [aws_eks_cluster.kr_cluster]
}

resource "aws_eks_access_policy_association" "kr_cluster_access_policy" {
  for_each = local.cluster_access_map

  cluster_name  = each.value.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type = each.value.access_scope
  }

  depends_on = [aws_eks_access_entry.kr_cluster_access]
}
