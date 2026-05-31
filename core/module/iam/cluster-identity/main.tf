# =============================================================================
# main.tf — IAM Cluster Identity Module
#
# Creates:
# 1. IAM role trust policies from cluster_identity_roles templates.
# 2. IAM roles for cluster access.
# 3. IAM groups and per-group inline assume-role policies mapped by assume_role SID.
# 4. IAM users and user-group memberships.
# 5. EKS access entries mapping each created role to system:masters.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  roles_map = {
    for r in var.cluster_identity_roles : "${r.cluster_name}__${r.name}" => r
  }

  role_sid_map = {
    for k, r in local.roles_map : "${r.cluster_name}__${r.sid}" => k
  }

  groups_map = {
    for g in var.cluster_identity_groups : "${g.cluster_name}__${g.name}" => g
  }

  users_map = {
    for u in var.cluster_identity_users : "${u.cluster_name}__${u.group_name}__${u.name}" => u
    if u.enabled
  }

  groups_with_role_map = {
    for k, g in local.groups_map : k => merge(
      g,
      {
        role_key = local.role_sid_map["${g.cluster_name}__${g.assume_role}"]
      }
    )
    if contains(keys(local.role_sid_map), "${g.cluster_name}__${g.assume_role}")
  }

  users_with_existing_group = {
    for k, u in local.users_map : k => u
    if contains(keys(local.groups_map), "${u.cluster_name}__${u.group_name}")
  }

  users_with_existing_group_and_role = {
    for k, u in local.users_with_existing_group : k => merge(
      u,
      {
        role_key = local.groups_with_role_map["${u.cluster_name}__${u.group_name}"].role_key
      }
    )
    if contains(keys(local.groups_with_role_map), "${u.cluster_name}__${u.group_name}")
  }

  role_kubernetes_groups = {
    for role_key in keys(local.roles_map) : role_key => distinct(flatten([
      for u in values(local.users_with_existing_group_and_role) :
      u.role_key == role_key ? (length(u.k8group) > 0 ? u.k8group : ["system:masters"]) : []
    ]))
  }
}

data "aws_iam_policy_document" "kr_cluster_role_assume_role_policy" {
  for_each = local.roles_map

  version = each.value.version

  statement {
    effect  = each.value.effect
    actions = each.value.actions

    principals {
      type = "AWS"
      identifiers = [
        replace(each.value.principal, "$${account_id}", data.aws_caller_identity.current.account_id)
      ]
    }
  }
}

resource "aws_iam_role" "kr_cluster_role" {
  for_each = local.roles_map

  name               = each.value.name
  description        = each.value.description
  assume_role_policy = aws_iam_policy_document.kr_cluster_role_assume_role_policy[each.key].json

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

data "aws_iam_policy_document" "kr_cluster_group_managed_policy_doc" {
  for_each = local.roles_map

  statement {
    sid       = "AssumeClusterRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.kr_cluster_role[each.key].arn]
  }
}

resource "aws_iam_policy" "kr_cluster_group_managed_policy" {
  for_each = local.roles_map

  name        = "${each.value.name}-assume-policy"
  description = "Managed assume-role policy for ${each.value.name}"
  policy      = data.aws_iam_policy_document.kr_cluster_group_managed_policy_doc[each.key].json

  tags = merge(
    var.common_tags,
    {
      Name = "${each.value.name}-assume-policy"
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_iam_group" "kr_group" {
  for_each = local.groups_map

  name = each.value.name
}

resource "aws_iam_group_policy" "kr_assume_eks_role" {
  for_each = local.groups_with_role_map

  name  = "${replace(each.value.name, "_", "-")}-assume-role"
  group = aws_iam_group.kr_group[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.kr_cluster_role[each.value.role_key].arn
      }
    ]
  })
}

resource "aws_iam_user" "kr_user" {
  for_each = local.users_with_existing_group

  name          = each.value.name
  force_destroy = each.value.force_destroy
  path          = trimspace(each.value.namespace) != "" ? "/${trim(each.value.namespace, "/")}/" : "/"

  tags = merge(
    var.common_tags,
    {
      Name        = each.value.name
      Description = each.value.description
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_iam_user_group_membership" "kr_user_group_membership" {
  for_each = local.users_with_existing_group

  user = aws_iam_user.kr_user[each.key].name
  groups = [
    aws_iam_group.kr_group["${each.value.cluster_name}__${each.value.group_name}"].name
  ]

  depends_on = [
    aws_iam_user.kr_user,
    aws_iam_group.kr_group,
  ]
}

resource "aws_eks_access_entry" "kr_cluster_access_entry" {
  for_each = local.roles_map

  cluster_name      = each.value.cluster_name
  principal_arn     = aws_iam_role.kr_cluster_role[each.key].arn
  type              = "STANDARD"
  kubernetes_groups = length(local.role_kubernetes_groups[each.key]) > 0 ? local.role_kubernetes_groups[each.key] : ["system:masters"]

  tags = merge(
    var.common_tags,
    {
      Name = "${each.value.cluster_name}__${each.value.name}"
    }
  )

  depends_on = [aws_iam_role.kr_cluster_role]
}
