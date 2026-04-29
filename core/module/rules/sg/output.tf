# =============================================================================
# output.tf — Security Group Module
# =============================================================================

# List of created security group objects carrying the AWS resource id,
# the logical id reference (used in rule links), and the resource name.
output "security_groups" {
  description = "List of created security groups with AWS resource id, logical id reference, and name."
  value = [
    for ref, sg in aws_security_group.kr_security_group : {
      id   = sg.id    # AWS resource ID  (sg-xxxxxxxx)
      ref  = ref      # Logical id reference (e.g. kr-app-rst)
      name = sg.name  # Name tag value
    }
  ]
}

# Convenience map of logical id reference → AWS security group resource ID.
# Useful when other modules need to look up an SG by its zone id.
output "security_group_ids" {
  description = "Map of logical id reference to AWS security group resource ID."
  value = {
    for ref, sg in aws_security_group.kr_security_group : ref => sg.id
  }
}
