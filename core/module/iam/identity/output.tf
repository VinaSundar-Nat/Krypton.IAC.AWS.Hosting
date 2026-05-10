# =============================================================================
# output.tf — IAM Identity Module
# =============================================================================

# List of created IAM groups with name and arn.
output "groups" {
  description = "List of created IAM groups with name and arn."
  value = [
    for name, group in aws_iam_group.kr_groups : {
      name = group.name
      arn  = group.arn
    }
  ]
}

# List of created IAM users with name and arn.
output "users" {
  description = "List of created IAM users with name and arn."
  value = [
    for name, user in aws_iam_user.kr_user : {
      name = user.name
      arn  = user.arn
    }
  ]
}

# Map of group name → group ARN.
output "group_arns" {
  description = "Map of IAM group name to ARN."
  value = {
    for name, group in aws_iam_group.kr_groups : group.name => group.arn
  }
}

# Map of user name → user ARN.
output "user_arns" {
  description = "Map of IAM user name to ARN."
  value = {
    for name, user in aws_iam_user.kr_user : user.name => user.arn
  }
}
