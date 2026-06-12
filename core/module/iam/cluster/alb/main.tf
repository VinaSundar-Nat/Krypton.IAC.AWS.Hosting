# =============================================================================
# main.tf — IAM Cluster ALB Module
#
# Creates:
# 1. IAM policies for Load Balancer Controller (loaded from template files).
# 2. IAM role policy attachments linking policies to Pod Identity roles.
# 3. EKS Pod Identity associations linking IAM roles to Kubernetes service accounts.
#
# Only processes roles with pod_identity.required = true.
# Policy templates are sourced from core/module/iam/template/*.json.
# =============================================================================

locals {
  # Flatten all pod_identity role → policy combinations for policy creation
  lbc_policies_map = var.pod_identity.required ? {
    for pair in flatten([
      for r in var.pod_identity.roles : [
        for p in r.policy : {
          key         = "${r.role_name}__${p.name}"
          role_name   = r.role_name
          policy_name = p.name
          policy_tmpl = p.template_location
          description = r.description
        }
      ]
    ]) : pair.key => pair
  } : {}

  # Flatten pod_identity roles for Pod Identity association creation
  lbc_roles_map = var.pod_identity.required ? {
    for r in var.pod_identity.roles : r.role_name => r
  } : {}
}

# ── IAM Policy for Load Balancer Controller ──────────────────────────────────
# Creates a managed IAM policy from the template file for each LBC policy entry.
resource "aws_iam_policy" "kr_lbc_policy" {
  for_each = local.lbc_policies_map

  name        = each.value.policy_name
  description = each.value.description
  policy      = file("${path.module}/../../template/${each.value.policy_tmpl}")

  tags = merge(
    var.common_tags,
    {
      Name = each.value.policy_name
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── IAM Role Policy Attachment ───────────────────────────────────────────────
# Attaches the LBC policy to the Pod Identity IAM role.
resource "aws_iam_role_policy_attachment" "kr_lbc_attach" {
  for_each = local.lbc_policies_map

  policy_arn = aws_iam_policy.kr_lbc_policy[each.key].arn
  role       = each.value.role_name
}

# ── EKS Pod Identity Association ─────────────────────────────────────────────
# Links the IAM role to the Kubernetes service account for Pod Identity injection.
resource "aws_eks_pod_identity_association" "kr_lbc_auth" {
  for_each = local.lbc_roles_map

  cluster_name    = var.pod_identity.cluster_name
  namespace       = each.value.service_account.namespace
  service_account = each.value.service_account.name
  role_arn        = var.cluster_role_arns[each.key]

  tags = merge(
    var.common_tags,
    {
      Name = "${each.key}-pod-identity-association"
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}
