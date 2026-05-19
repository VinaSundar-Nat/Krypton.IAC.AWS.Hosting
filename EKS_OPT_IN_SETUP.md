# EKS Opt-In Variable Setup

## Overview
The `opt-in` flag from `environment/dev/hosting/k8surface.yml` has been mapped to a Terraform variable that determines whether EKS infrastructure is required.

## Changes Made

### 1. Variable Definition
**File:** [core/variables/k8hosting.tf](core/variables/k8hosting.tf)

Added new variable `eks_enabled`:
```hcl
variable "eks_enabled" {
  description = "Feature flag indicating whether EKS is required for this component (opt-in from k8surface.yml)."
  type        = bool
  default     = false
}
```

### 2. Template Files
**Files Updated:**
- [core/variables/k8hosting.auto.tfvars.tpl](core/variables/k8hosting.auto.tfvars.tpl)
- [core/variables/k8hosting.auto.tfvars](core/variables/k8hosting.auto.tfvars)

Added new line in templates:
```hcl
eks_enabled = REPLACE_EKS_ENABLED
```

The `REPLACE_EKS_ENABLED` token is populated during variable substitution.

### 3. Variable Generation Script
**File:** [scripts/configuration/k8hosting-vars.sh](scripts/configuration/k8hosting-vars.sh)

Added extraction logic:
```bash
# Extract EKS enabled flag from component.opt-in
EKS_ENABLED="$(yq "${SEL} | .opt-in" "${K8HOSTING_YAML}")"
[[ -z "$EKS_ENABLED" || "$EKS_ENABLED" == "null" ]] && EKS_ENABLED="false"
```

And substitution:
```bash
_sub "${K8_DEST}" "REPLACE_EKS_ENABLED" "${EKS_ENABLED}"
```

## How It Works

### Data Flow
1. **Source:** `environment/dev/hosting/k8surface.yml`
   ```yaml
   component:
     - sid: "kr-carevo"
       opt-in: true          # ← Control flag
       cluster: [...]
   ```

2. **Processing:** `scripts/configuration/k8hosting-vars.sh`
   - Extracts component matching SID (kr-carevo)
   - Reads `.opt-in` field
   - Defaults to `false` if missing/null
   - Substitutes into template

3. **Generated:** `core/variables/k8hosting.auto.tfvars`
   ```hcl
   eks_enabled = true
   ```

4. **Consumed:** Terraform variable `var.eks_enabled`

## Usage in Terraform

### Conditional EKS Module Deployment

In [core/main.tf](core/main.tf), add conditional module invocation:

```hcl
# =============================================================================
# EKS Module – creates EKS clusters with managed nodegroups (conditional)
# =============================================================================
module "deploy-kr-eks-clusters" {
  source = "./module/hosting/k8/cluster"
  
  count = var.eks_enabled ? 1 : 0  # Only deploy if opt-in is true
  
  eks_clusters = var.eks_clusters
  
  # Add other required inputs...
  
  depends_on = [
    module.deploy-kr-iam-eks-roles,
    module.deploy-kr-subnets,
    module.deploy-kr-security-groups,
  ]
}
```

### Reference EKS Enabled Status

In any Terraform module or locals:

```hcl
locals {
  eks_required = var.eks_enabled
}

// Conditionally create resources that depend on EKS
resource "aws_something" "example" {
  count = local.eks_required ? 1 : 0
  // ...
}
```

## Testing

### Verify Variable Population

After running the variable substitution:
```bash
./scripts/configuration/replace-vars.sh kr-carevo dev
```

Check the generated file:
```bash
cat core/variables/k8hosting.auto.tfvars | grep eks_enabled
```

Expected output (with opt-in: true):
```
eks_enabled = true
```

### Terraform Plan

```bash
cd core
terraform plan -var-file=variables/k8hosting.auto.tfvars
```

The variable `var.eks_enabled` will be available and set to the value from your YAML.

## Notes

- **Default Value:** `false` — EKS is not deployed unless explicitly opted in
- **Source of Truth:** `environment/dev/hosting/k8surface.yml` under `component.opt-in`
- **Non-Destructive:** Variable is purely informational; no modules use it yet (awaiting module implementation)
- **Environment Specific:** Each environment can have its own opt-in setting in the respective `environment/<ENV>/hosting/k8surface.yml`
