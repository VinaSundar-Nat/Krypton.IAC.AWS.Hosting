# =============================================================================
# output.tf — Network ACL Module
# =============================================================================

# List of created Network ACL objects carrying the AWS resource id,
# the logical id reference (used in rule links), and the resource name.
output "network_acls" {
  description = "List of created Network ACLs with AWS resource id, logical id reference, and name."
  value = [
    for ref, nacl in aws_network_acl.kr_network_acl : {
      id   = nacl.id    # AWS resource ID  (acl-xxxxxxxx)
      ref  = ref        # Logical id reference (e.g. kr-ect-nacl)
      name = nacl.tags["Name"]
    }
  ]
}

# Convenience map of logical id reference → AWS Network ACL resource ID.
# Useful when other modules need to look up a NACL by its zone id.
output "network_acl_ids" {
  description = "Map of logical id reference to AWS Network ACL resource ID."
  value = {
    for ref, nacl in aws_network_acl.kr_network_acl : ref => nacl.id
  }
}
