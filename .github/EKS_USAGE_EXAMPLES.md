# Example: Using eks_enabled in core/main.tf

Many of the existing network, security, and IAM resources depend on whether EKS is deployed.
This example shows how to conditionally deploy EKS and reference the flag in your Terraform code.

## Example 1: Conditional EKS Cluster Module Deployment

```hcl
# =============================================================================
# EKS Module – creates EKS clusters with managed nodegroups (conditional)
# =============================================================================
module "deploy-kr-eks-clusters" {
  source = "./module/hosting/k8/cluster"
  
  # Only deploy if eks_enabled is true
  count = var.eks_enabled ? 1 : 0
  
  eks_clusters = var.eks_clusters
  
  depends_on = [
    module.deploy-kr-iam-eks-roles,
    module.deploy-kr-subnets,
    module.deploy-kr-security-groups,
  ]
}
```

## Example 2: Using Variable in Locals for Dependent Resources

```hcl
locals {
  # Feature flags
  eks_required = var.eks_enabled
  
  # Tags for resources that depend on EKS
  eks_tags = local.eks_required ? {
    "eks-required" = "true"
    "deployment"   = "kubernetes"
  } : {}
}

# Example: Create security group rules only if EKS is enabled
resource "aws_security_group_rule" "eks_worker_ingress" {
  count = local.eks_required ? 1 : 0
  
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = module.deploy-kr-security-groups.eks_worker_sg_id
  description       = "Allow EKS API access from VPC"
}
```

## Example 3: Conditional Output Export

```hcl
# core/output.tf
output "eks_enabled" {
  description = "Whether EKS is deployed for this component"
  value       = var.eks_enabled
}

output "eks_clusters" {
  description = "Deployed EKS clusters (empty if eks_enabled is false)"
  value       = var.eks_enabled ? var.eks_clusters : []
}
```

## Example 4: Local Values for Complex Logic

```hcl
locals {
  eks_deployment_config = var.eks_enabled ? {
    cluster_log_retention_days = 7
    enable_control_plane_logs  = true
    enable_node_monitoring     = true
    auto_scaling_enabled       = true
  } : {
    cluster_log_retention_days = 0
    enable_control_plane_logs  = false
    enable_node_monitoring     = false
    auto_scaling_enabled       = false
  }
  
  # Use in module
  eks_config = merge(
    local.eks_deployment_config,
    {
      region = var.aws_region
      tags   = var.common_tags
    }
  )
}
```

## Integration Points

### 1. Before EKS Module (Always Created)
- VPC Module
- Subnet Module
- Security Groups Module
- IAM Roles Module (includes EKS roles)
- NetworkACL Module

### 2. EKS Module (Conditional on eks_enabled)
- Uses subnets from Subnet Module
- Uses security groups from SG Module  
- Uses IAM roles from IAM Roles Module

### 3. Dependent on EKS (Conditional)
- Helm deployments (if using Terraform + Helm)
- Application-specific security group rules
- Application load balancer target groups

## Testing

### Test with opt-in: true
```bash
# Add to k8surface.yml
component:
  - sid: kr-carevo
    opt-in: true

# Generate variables
./scripts/configuration/replace-vars.sh kr-carevo dev

# Check terraform will deploy EKS
terraform plan -target=module.deploy-kr-eks-clusters
```

### Test with opt-in: false
```bash
# Modify k8surface.yml
component:
  - sid: kr-carevo
    opt-in: false

# Generate variables
./scripts/configuration/replace-vars.sh kr-carevo dev

# Check terraform skips EKS (count condition evaluates to false, so module not deployed)
terraform plan
```
