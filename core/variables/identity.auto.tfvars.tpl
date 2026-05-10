# =============================================================================
# core/variables/identity.auto.tfvars — MASTER TEMPLATE
#
# REPLACE_* tokens are substituted by scripts/replace-vars.sh at runtime.
# Restored to this state by scripts/revert-master-vars.sh after terraform runs.
#
# Source:
#   environment/<ENV>/platform/identity.yml  → IAM policies, groups, users,
#                                              cluster and nodegroup roles
#
# DO NOT edit REPLACE_* tokens — edit the source YAML files instead.
# =============================================================================

# Global IAM policies — from identity.yml component.global.policy[]
iam_policies = REPLACE_IAM_POLICIES

# Global IAM groups — from identity.yml component.global.group[]
iam_groups = REPLACE_IAM_GROUPS

# Global IAM users — from identity.yml component.global.user[]
iam_users = REPLACE_IAM_USERS

# EKS cluster IAM roles — from identity.yml component.cluster[].role[]
cluster_roles = REPLACE_CLUSTER_ROLES

# EKS cluster managed policy attachments — from identity.yml component.cluster[].policy[]
cluster_policies = REPLACE_CLUSTER_POLICIES

# EKS worker nodegroup IAM roles — from identity.yml component.nodegroup[].role[]
nodegroup_roles = REPLACE_NODEGROUP_ROLES

# EKS worker nodegroup managed policy attachments — from identity.yml component.nodegroup[].policy[]
nodegroup_policies = REPLACE_NODEGROUP_POLICIES
