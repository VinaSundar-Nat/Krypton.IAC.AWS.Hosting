# Create Custom Namespace in Carevo Dev Clusters

## Feature Dated : 2026/June/02

## Why

Logical separation of application tiers using Kubernetes namespaces. This creates virtual fencing between zones and improves workload isolation.

It also enables per-namespace Resource Quotas so multiple programs can share the same cluster safely, while allowing RBAC controls to be scoped to the relevant tribe.

## What

Introduce configuration-driven namespace definitions with labels for each environment, and use the Terraform Kubernetes provider to create namespaces.

Example: `carevo-web-ict-ns` is defined in `environment/dev/hosting/k8surface.yml` per cluster definition. Additional namespace entries are added for required scopes, initially separated into three layers based on project boundaries.

```yaml
namespace:
  - name: "carevo-web-ict-ns"
    description: "Namespace for Carevo internet-facing web applications"
    labels:
      team: "Carevo web hosting"
      environment: "dev"
      organization: "Krypton"
      program: "Carevo"
      application: "KrCE-Web"
      layer: "Web Tier"
      zone: "ict"
```

## Constraints

### Must

- Namespace definitions must be sourced from environment YAML (`environment/<env>/hosting/k8surface.yml`) and not hardcoded in Terraform module logic.
- Namespace creation must occur only after the target EKS cluster is created and provider authentication is ready.
- Labels must be consistently applied for governance fields such as team, environment, organization, program, application, layer, and zone.
- Kubernetes provider authentication must support both local runner and GHA execution paths using short-lived AWS EKS tokens.
- Cluster endpoint and decoded certificate authority data must be available as Terraform outputs for provider configuration.

### Must Not

- Must not create namespaces for clusters or components that are not opted in by configuration.
- Must not introduce static credentials, secrets, or account-specific sensitive data into Terraform code, scripts, or generated vars.
- Must not bypass existing module boundaries or break current input/output contracts across hosting modules.
- Must not alter unrelated generated artifacts outside the namespace and provider wiring required for this feature.

### Out of Scope

- Migrating existing workloads into newly created namespaces.
- Implementing RBAC roles, role bindings, or quota objects beyond namespace creation and labeling.
- Changes to non-dev environments unless explicitly requested in a follow-up iteration.
- Refactoring unrelated Terraform modules or redesigning cluster provisioning flow.

## Current State

Cluster creation completed.

## Tasks

TASK1:

Add the Kubernetes provider in `core/versions.tf`:

```hcl
kubernetes = {
  source  = "hashicorp/kubernetes"
  version = "~> 2.20"
}
```

TASK2:

Create variable definitions for namespace input additions in `environment/dev/hosting/k8surface.yml`.

Define and wire Terraform variables in:

- `core/variables/k8hosting.tf`
- `core/variables/k8hosting.auto.tfvars`
- `core/variables/k8hosting.auto.tfvars.tpl`

Update `scripts/configuration/k8hosting-vars.sh` for replacement of the newly added variables, aligned with current script conventions.

TASK3:

Include namespace creation logic in `core/module/hosting/k8/namespace/main.tf` and set up matching input/output variables.

Create flattened local values if required by input structure. Namespace resources must depend on cluster readiness.

Reference structure:

```hcl
resource "kubernetes_namespace" "kr_cluster_namespace" {
  for_each = var.namespace_map

  metadata {
    name = each.value.name
    labels = each.value.labels
  }
}
```

TASK4:

Update deploy-kr-eks-cluster outputs to expose:

- `certificate_authority[0].data` (base64 decoded)
- cluster endpoint

If direct output from `core/module/hosting/k8/cluster/main.tf` resource `aws_eks_cluster` is not feasible, add `data "aws_eks_cluster"` and source values from data for output.

TASK5:

In `core/main.tf`, after cluster creation (`depends_on`), configure and authorize the Kubernetes provider.

Both runner and GHA access entries already exist and should be used.

Match cluster names from `environment/dev/hosting/k8surface.yml` and bind associated variables:

- certificate
- cluster endpoint
- cluster name

Use decoded certificate output from TASK4 and AWS CLI token generation for Terraform execution.

Reference structure:

```hcl
provider "kubernetes" {
  host                   = var.endpoint
  cluster_ca_certificate = var.certificate

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.clustername]
  }
}
```

TASK6:

Invoke the namespace module with required parameters after provider authorization succeeds. This must depend on TASK5 completion.

---

## Post-Implementation Review Checklist

This checklist should be verified after all tasks are completed and before testing begins.

### Code Structure & Contracts

- [ ] **TASK1**: `core/versions.tf` contains `hashicorp/kubernetes` provider with version constraint `~> 2.20`
- [ ] **TASK2**: `core/variables/k8hosting.tf` includes:
  - [ ] `eks_clusters` variable updated to include nested `namespace` object array
  - [ ] `namespace_map` variable added with proper type definition (map of namespace configs)
  - [ ] Namespace map keys follow `cluster_name:namespace_name` pattern
- [ ] **TASK2**: `core/variables/k8hosting.auto.tfvars.tpl` contains `REPLACE_NAMESPACE_MAP` token
- [ ] **TASK2**: `scripts/configuration/k8hosting-vars.sh`:
  - [ ] `_render_namespace_map()` helper function implemented and flattens cluster.namespace[] correctly
  - [ ] Extraction logic substitutes `REPLACE_NAMESPACE_MAP` in tfvars file
  - [ ] Script maintains idempotency for repeated runs
- [ ] **TASK3**: `core/module/hosting/k8/namespace/variable.tf` defines `namespace_map` input variable
- [ ] **TASK3**: `core/module/hosting/k8/namespace/main.tf` creates `kubernetes_namespace` resources with:
  - [ ] `for_each` loop over `var.namespace_map`
  - [ ] Metadata includes namespace `name` and `labels`
  - [ ] No hardcoded namespace values
- [ ] **TASK3**: `core/module/hosting/k8/namespace/output.tf` exports:
  - [ ] `namespaces` - complete namespace resource objects
  - [ ] `namespace_names` - list of created namespace names
  - [ ] `namespace_ids` - map of keys to namespace names
- [ ] **TASK4**: `core/module/hosting/k8/cluster/output.tf`:
  - [ ] `cluster_endpoints` output exists (map of cluster name to endpoint)
  - [ ] `cluster_certificate_authority` output exists (base64-encoded CA data)
  - [ ] `cluster_certificate_authority_decoded` output exists (base64-decoded CA data for provider use)
- [ ] **TASK5**: `core/variables.tf` includes:
  - [ ] `kubernetes_host` variable for API endpoint
  - [ ] `kubernetes_cluster_ca_certificate` variable for decoded CA cert (marked sensitive)
  - [ ] `kubernetes_cluster_name` variable for cluster name in token generation
- [ ] **TASK5**: `core/main.tf` contains `provider "kubernetes"` block with:
  - [ ] `host` references `var.kubernetes_host`
  - [ ] `cluster_ca_certificate` references `var.kubernetes_cluster_ca_certificate`
  - [ ] `exec` auth block uses `aws eks get-token --cluster-name` command
  - [ ] Provider depends on cluster and nodegroup modules
- [ ] **TASK6**: `core/main.tf` includes `module "deploy-kr-eks-namespaces"`:
  - [ ] Sources `./module/hosting/k8/namespace`
  - [ ] Passes `var.namespace_map` to the module
  - [ ] Depends on cluster, nodegroup, and provider readiness

### YAML Source & Variable Generation

- [ ] `environment/dev/hosting/k8surface.yml`:
  - [ ] Contains `namespace` array under targeted cluster(s)
  - [ ] Each namespace includes: `name`, `sid`, `description`, `labels`
  - [ ] Labels include standard governance fields: `team`, `environment`, `organization`, `program`, `application`, `layer`, `zone`
- [ ] Running `scripts/configuration/replace-vars.sh <sid> dev` correctly:
  - [ ] Generates `core/variables/k8hosting.auto.tfvars` with populated values
  - [ ] `namespace_map` is rendered as valid HCL map with cluster-prefixed keys
  - [ ] No hardcoded namespace payloads appear in generated tfvars

### Terraform Validation

- [ ] `terraform init` from `core/` resolves without provider conflicts
- [ ] `terraform validate` from `core/` passes after var generation
- [ ] `terraform fmt -recursive core/` applies consistent formatting
- [ ] Plan execution shows:
  - [ ] Kubernetes provider initializes successfully
  - [ ] No authentication errors or missing variable warnings
  - [ ] Namespace resources are created only for opted-in, managed clusters
  - [ ] No unrelated resources are planned for modification

### Dependency & Auth Path Integrity

- [ ] Kubernetes provider authorization supports both execution paths:
  - [ ] Local runner (IAM Roles Anywhere) compatibility maintained
  - [ ] GHA (OIDC web identity) compatibility maintained
- [ ] No static credentials, secrets, or AWS account IDs in Terraform code or generated vars
- [ ] Module dependencies prevent namespace creation before:
  - [ ] Cluster is fully provisioned
  - [ ] Nodegroups are ready
  - [ ] Kubernetes provider is authorized
- [ ] Existing module contracts remain intact:
  - [ ] No breaking changes to cluster/nodegroup/IAM module inputs or outputs
  - [ ] No modifications to unrelated generated artifacts

### Opt-In & Filtering

- [ ] Non-opted-in clusters/components do NOT trigger namespace resource creation
- [ ] `eks_enabled = false` correctly prevents all namespace resource planning
- [ ] Only `mode = "managed"` clusters are considered for namespace provisioning

### Testing Execution (To be performed after code review)

**Prerequisite**: All above checklist items verified.

- [ ] Run `./scripts/runner.sh dev plan <sid>` and confirm:
  - [ ] Terraform plan completes without errors
  - [ ] Namespace resources appear in plan for each defined namespace
  - [ ] Labels from YAML appear correctly in planned namespaces
  - [ ] No regressions in existing cluster/nodegroup resources
- [ ] Inspect generated `core/variables/k8hosting.auto.tfvars` for:
  - [ ] Valid HCL syntax
  - [ ] Correct `namespace_map` structure with cluster prefixes
  - [ ] All namespace labels preserved
- [ ] Optional: Apply infrastructure (if test environment available):
  - [ ] Namespaces are created in the cluster
  - [ ] Labels are applied correctly
  - [ ] Namespace access from cluster endpoint works with generated auth tokens
