# =============================================================================
# output.tf — IAM Policy Module
# =============================================================================

# List of all created IAM policy objects with name, id, and arn.
output "policies" {
  description = "List of created IAM policy objects with name, id, and arn."
  value = [
    for name, policy in aws_iam_policy.kr_policy : {
      name = policy.name
      id   = policy.id
      arn  = policy.arn
    }
  ]
}

# Map of policy name → ARN — consumed by the identity module for group attachments.
output "policy_arns" {
  description = "Map of policy name to ARN for use by group/role policy attachment resources."
  value = {
    for name, policy in aws_iam_policy.kr_policy : policy.name => policy.arn
  }
}
