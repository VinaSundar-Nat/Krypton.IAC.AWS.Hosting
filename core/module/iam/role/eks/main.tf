# =============================================================================
# main.tf — EKS IAM Role Module - Cluster and Nodegroup Roles
#
# Creates IAM roles and managed policy attachments for EKS cluster service
# roles and worker nodegroup instance roles.
#
# Sourced from identity.yml component.cluster[] and component.nodegroup[].
#
# Step 1 — Build locals: maps of cluster/nodegroup roles keyed by name, and
#           flattened (policy, role, arn) attachment triplets filtered to
#           entries where enabled = true.
#
# Step 2 — Create aws_iam_role for every cluster role and attach the
#           referenced managed policies via aws_iam_role_policy_attachment.
#
# Step 3 — Create aws_iam_role for every worker nodegroup role and attach
#           the referenced managed policies via aws_iam_role_policy_attachment.
# =============================================================================

# ── Step 1: Locals ─────────────────────────────────────────────────────────────
locals {
  # Map of EKS cluster roles keyed by name.
  cluster_roles_map = {
    for r in var.cluster_roles : r.name => r
  }

  # Map of EKS worker nodegroup roles keyed by name.
  nodegroup_roles_map = {
    for r in var.nodegroup_roles : r.name => r
  }

  # Flatten cluster policy → role → arn triplets.
  # One aws_iam_role_policy_attachment is created per (role, arn) pair.
  # Policy entries with enabled = false are excluded.
  # Key: "${policy_name}__${role_name}__${arn}" — unique per attachment.
  cluster_policy_attachments = {
    for item in flatten([
      for pol in var.cluster_policies : [
        for role_name in pol.roles : [
          for arn in pol.arns : {
            key       = "${pol.name}__${role_name}__${arn}"
            role_name = role_name
            arn       = arn
          }
        ]
      ]
      if pol.enabled
    ]) : item.key => item
  }

  # Flatten nodegroup policy → role → arn triplets.
  # Policy entries with enabled = false are excluded.
  nodegroup_policy_attachments = {
    for item in flatten([
      for pol in var.nodegroup_policies : [
        for role_name in pol.roles : [
          for arn in pol.arns : {
            key       = "${pol.name}__${role_name}__${arn}"
            role_name = role_name
            arn       = arn
          }
        ]
      ]
      if pol.enabled
    ]) : item.key => item
  }
}

# ── Step 2a: EKS Cluster IAM Roles ────────────────────────────────────────────
resource "aws_iam_role" "kr_cluster_roles" {
  for_each = local.cluster_roles_map

  name               = each.value.name
  description        = each.value.description
  assume_role_policy = each.value.assume_role_policy

  tags = merge(
    var.common_tags,
    {
      Name = each.value.name
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── Step 2b: Cluster Role → Managed Policy Attachments ────────────────────────
resource "aws_iam_role_policy_attachment" "kr_cluster_role_policy_attachment" {
  for_each = local.cluster_policy_attachments

  role       = aws_iam_role.kr_cluster_roles[each.value.role_name].name
  policy_arn = each.value.arn

  depends_on = [aws_iam_role.kr_cluster_roles]
}

# ── Step 3a: EKS Worker Nodegroup IAM Roles ───────────────────────────────────
resource "aws_iam_role" "kr_nodegroup_roles" {
  for_each = local.nodegroup_roles_map

  name               = each.value.name
  description        = each.value.description
  assume_role_policy = each.value.assume_role_policy

  tags = merge(
    var.common_tags,
    {
      Name = each.value.name
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── Step 3b: Nodegroup Role → Managed Policy Attachments ─────────────────────
resource "aws_iam_role_policy_attachment" "kr_nodegroup_role_policy_attachment" {
  for_each = local.nodegroup_policy_attachments

  role       = aws_iam_role.kr_nodegroup_roles[each.value.role_name].name
  policy_arn = each.value.arn

  depends_on = [aws_iam_role.kr_nodegroup_roles]
}
