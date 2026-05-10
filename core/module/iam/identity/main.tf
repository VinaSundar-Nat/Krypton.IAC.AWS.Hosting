# =============================================================================
# main.tf — IAM Identity Module - Global Cluster Management 
#
# Manages global IAM groups, group-to-policy associations, IAM users, and
# user-to-group memberships sourced from identity.yml component.global.
#
# Step 1 — Build locals: a map of groups, enabled users, and a flattened list
#           of (group, policy) pairs for policy attachment resources.
#
# Step 2 — Create aws_iam_group for every group in var.iam_groups and attach
#           the referenced policies via aws_iam_group_policy_attachment.
#           Policy ARNs are resolved by name from var.policy_arns (supplied by
#           the policy module output).
#
# Step 3 — Create aws_iam_user for every enabled user in var.iam_users and
#           establish group membership via aws_iam_user_group_membership.
#           Users with enabled = false are skipped without deletion.
# =============================================================================

# ── Step 1: Locals ────────────────────────────────────────────────────────────
locals {
  # Map of all IAM groups keyed by name.
  groups_map = {
    for g in var.iam_groups : g.name => g
  }

  # Map of enabled IAM users keyed by name.
  # Users with enabled = false are excluded from creation.
  users_map = {
    for u in var.iam_users : u.name => u
    if u.enabled
  }

  # Flatten group → policy associations into individual (group_name, policy_name) pairs.
  # One aws_iam_group_policy_attachment is created per pair.
  # Map keys are derived only from static input (iam_groups), so for_each is deterministic at plan time.
  # Policy ARNs are resolved at resource apply time via var.policy_arns lookup.
  group_policy_flat = flatten([
    for g in var.iam_groups : [
      for policy_name in g.policies : {
        key         = "${g.name}__${policy_name}"
        group_name  = g.name
        policy_name = policy_name
      }
    ]
  ])

  group_policy_map = {
    for item in local.group_policy_flat : item.key => item
  }
}

# ── Step 2a: IAM Groups ───────────────────────────────────────────────────────
resource "aws_iam_group" "kr_groups" {
  for_each = local.groups_map
  name     = each.value.name
}

# ── Step 2b: Group → Policy Attachments ───────────────────────────────────────
resource "aws_iam_group_policy_attachment" "kr_group_policy_association" {
  for_each = local.group_policy_map

  group      = aws_iam_group.kr_groups[each.value.group_name].name
  policy_arn = var.policy_arns[each.value.policy_name]

  depends_on = [aws_iam_group.kr_groups]
}

# ── Step 3a: IAM Users ────────────────────────────────────────────────────────
resource "aws_iam_user" "kr_user" {
  for_each = local.users_map

  name = each.value.name

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

# ── Step 3b: User → Group Memberships ─────────────────────────────────────────
resource "aws_iam_user_group_membership" "kr_membership" {
  for_each = local.users_map

  user = aws_iam_user.kr_user[each.key].name

  # Resolve group names to the groups managed within this module.
  # Group names that are not present in groups_map are silently skipped.
  groups = [
    for grp_name in each.value.groups :
    aws_iam_group.kr_groups[grp_name].name
    if contains(keys(local.groups_map), grp_name)
  ]

  depends_on = [
    aws_iam_user.kr_user,
    aws_iam_group.kr_groups,
  ]
}
