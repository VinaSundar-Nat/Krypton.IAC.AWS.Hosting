# =============================================================================
# main.tf — IAM Policy Module
#
# Creates customer-managed aws_iam_policy for every entry in var.iam_policies.
#
# Step 1 — Look up the caller's AWS account ID so it can be substituted into
#           Resource ARN placeholders (${account_id}).
#
# Step 2 — For policies whose template_param is a non-empty JSON list, build
#           an aws_iam_policy_document data source with dynamic statements.
#           The literal string "${account_id}" in Resource ARNs is replaced
#           with the real account ID at evaluation time.
#
# Step 3 — Create one aws_iam_policy per entry; template_param-based policies
#           reference the generated document, others fall back to an empty
#           allow-nothing statement list.
# =============================================================================

# ── Step 1: Caller identity — used to expand ${account_id} in Resource ARNs ──
data "aws_caller_identity" "current" {}

locals {
  # Map of all policies keyed by name for for_each usage.
  policies_map = {
    for p in var.iam_policies : p.name => p
  }

  # Subset of policies whose template_param holds a non-empty JSON list.
  # An empty string, "null", or "[]" means no document is built.
  template_policies = {
    for name, p in local.policies_map : name => p
    if p.template_param != "" && p.template_param != "null" && p.template_param != "[]"
  }
}

# ── Step 2: Policy documents built from template_param statement lists ────────
# One data source per policy that carries a non-empty template_param.
# Dynamic statement blocks are decoded from the JSON-encoded list; the literal
# "${account_id}" placeholder in Resource ARNs is replaced with the actual ID.
data "aws_iam_policy_document" "kr_policy_document" {
  for_each = local.template_policies

  version = "2012-10-17"

  dynamic "statement" {
    for_each = jsondecode(each.value.template_param)
    content {
      effect = statement.value["Effect"]

      # Action may be a JSON array or a single string in the source YAML.
      actions = try(
        tolist(statement.value["Action"]),
        [tostring(statement.value["Action"])]
      )

      # Resource may be a JSON array or a single string.
      # Replace the literal "${account_id}" placeholder in every entry.
      resources = try(
        [for r in tolist(statement.value["Resource"]) :
          replace(r, "$${account_id}", data.aws_caller_identity.current.account_id)
        ],
        [replace(
          tostring(statement.value["Resource"]),
          "$${account_id}",
          data.aws_caller_identity.current.account_id
        )]
      )
    }
  }
}

# ── Step 3: IAM Policy resources ──────────────────────────────────────────────
# One aws_iam_policy per entry in var.iam_policies.
# Policies with a valid template_param use the generated document JSON;
# any future entries without template_param fall back to an empty statement list.
resource "aws_iam_policy" "kr_policy" {
  for_each = local.policies_map

  name        = each.value.name
  description = each.value.description

  policy = (
    contains(keys(local.template_policies), each.key)
    ? data.aws_iam_policy_document.kr_policy_document[each.key].json
    : "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  )

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
