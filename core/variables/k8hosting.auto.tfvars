# =============================================================================
# core/variables/k8hosting.auto.tfvars — MASTER TEMPLATE
#
# REPLACE_* tokens are substituted by scripts/replace-vars.sh at runtime.
# Restored to this state by scripts/revert-master-vars.sh after terraform runs.
#
# Source:
#   environment/<ENV>/hosting/k8surface.yml  → EKS clusters and nodegroups
#
# DO NOT edit REPLACE_* tokens — edit the source YAML files instead.
# =============================================================================

# EKS enabled flag — from k8surface.yml component.opt-in
eks_enabled = REPLACE_EKS_ENABLED

# EKS cluster configurations with nested nodegroups — from k8surface.yml component.cluster[]
eks_clusters = REPLACE_EKS_CLUSTERS
