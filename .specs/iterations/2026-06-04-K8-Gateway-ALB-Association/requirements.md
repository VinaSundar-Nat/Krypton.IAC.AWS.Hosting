# EKS Pod Identity and ALB Gateway Association

## Feature Dated: 2026/June/09

## Why

Secure workload identity without hardcoded credentials is foundational to AWS security best practices (application security pillar). EKS Pod Identity simplifies this by eliminating the administrative overhead that IRSA (IAM Roles for Service Accounts) created, particularly during cluster autoscaling.

This feature enables the AWS Load Balancer Controller add-on to authenticate with AWS services securely and dynamically, and provisions Application Load Balancers (ALBs) to route external traffic into the cluster across multiple subnets and security boundaries.

## What

Provision EKS Pod Identity and secure cluster add-on authentication for the AWS Load Balancer Controller. Create an ALB for traffic routing across public and private subnets.

### Infrastructure Components

1. **Pod Identity IAM Role** – `kr-carevo-dev-cluster-lbc-role` (Load Balancer Controller trust policy)
2. **Pod Identity Association** – Links the role to the service account in `kube-system` namespace
3. **Pod Identity Add-on** – `eks-pod-identity-agent` for dynamic credential injection
4. **IAM Policy for LBC** – Load Balancer Controller permissions attached to the role
5. **Service Account** – `kr-carevo-dev-lbc-sa` in `kube-system` namespace for workload identity
6. **Helm Release** – AWS Load Balancer Controller v2.x deployment

### Network Placement

- **Public ALB** – Associated with public subnet (`ect`) and internet-facing Gateway
- **Private ALB** – Associated with private subnets (`rst`, `ict`) and internal Gateway
- Routes traffic to pods based on HTTPRoute configurations (out of scope for this iteration)

## Constraints

### Must

- Pod Identity role definitions must follow naming convention: `kr-carevo-<env>-<component>-role` (e.g., `kr-carevo-dev-cluster-lbc-role`)
- Trust policy principal format must accept both `Service` type (for Pod Identity) and `AWS` type (for future admin roles), with optional `$${account_id}` placeholder substitution for AWS principals only
- IAM policies must be sourced from templates (`core/module/iam/template/*.json`) and not hardcoded in Terraform
- Pod Identity configuration must be driven from `environment/dev/platform/identity.yml` under `pod_identity` section
- Load Balancer Controller configuration must be sourced from `environment/dev/hosting/k8surface.yml` under `lbc` section
- Role association and policy attachment logic must match role identifiers across identity and hosting configurations
- All add-ons, roles, and service accounts must be created conditionally based on cluster opt-in status
- Helm provider must support both local (AWS Roles Anywhere) and GHA (OIDC) authentication paths

### Must Not

- Must not create Pod Identity resources, roles, or service accounts for clusters that are not opted in
- Must not hardcode account IDs, cluster names, or environment-specific values in Terraform module code
- Must not introduce static credentials, API keys, or sensitive data into Terraform code or generated vars
- Must not bypass Pod Identity association; workloads must authenticate through assumed roles only
- Must not create ALBs or Gateway resources without proper security group and NACL rules in place
- Must not alter unrelated IAM, network, or cluster module boundaries or contracts
- Must not create HTTP Routes or Ingress resources in this iteration

### Out of Scope

- Implementing HTTPRoute or HTTPRuleGroup resources for HTTP/HTTPS routing
- Application onboarding and traffic configuration
- Changes to production or staging environments (dev environment only)
- Refactoring existing cluster, nodegroup, or IAM provisioning flows
- Implementing RBAC policies for service account usage
- Load Balancer Controller troubleshooting or operational runbooks

## Current State

- EKS cluster created and operational
- Subnets created across three availability zones (public ECT, private RST, private ICT)
- Security groups and NACLs defined for cluster communication
- Kubernetes provider authentication configured and operational
- Namespaces created for workload isolation

## Tasks

### TASK1: Extend IAM Principal Format for Pod Identity

**Objective:** Update the IAM policy document data source to support flexible principal definitions with type/value pairs.

**Details:**

In `core/module/iam/cluster/identity/main.tf`, update the `aws_iam_policy_document` data source to accept principals as an array of objects instead of a simple string:

```yaml
# Before (environment/dev/platform/identity.yml):
Principal: "arn:aws:iam::$${account_id}:root"

# After (environment/dev/platform/identity.yml):
Principal:
  - type: "AWS"
    value: "arn:aws:iam::$${account_id}:root"
  - type: "Service"
    value: "pods.eks.amazonaws.com"
```

Update the Terraform code to:
- Accept principal array in the configuration
- Iterate through principals and construct `principals` blocks in the policy document
- Apply account ID substitution only for `type = "AWS"` principals
- Preserve all other principal types as-is

**Code Refence:**

```hcl
# core/module/iam/cluster/identity/main.tf
principals {
  type        = each.value.principal.type
  identifiers = [
    each.value.principal.type == "AWS" 
      ? replace(each.value.principal.value, "$${account_id}", data.aws_caller_identity.current.account_id)
      : each.value.principal.value
  ]
}
```

**Scope Filtering:** Skip operations for roles prefixed with `adm-` (admin operations); only process roles required for LBC (prefixed with `lbc-`). This allows future admin role definitions without affecting LBC configuration.

---

### TASK2: Define Pod Identity Variables and Wire Variable Replacement

**Objective:** Introduce Pod Identity configuration into Terraform variables and generate them from YAML source.

**Details:**

1. Add `pod_identity` section to `environment/dev/platform/identity.yml`:

```yaml
pod_identity:
  roles:
    - role: "lbc-01"
      policy:
        - template_location: "loadbalancer.json"
          name: "kr-carevo-dev-lbc-pod-identity-policy"
      description: "IAM role policy mapping to EKS Pod Identity for Load Balancer Controller"
      service_account:
        name: "kr-carevo-dev-lbc-sa"
        namespace: "kube-system"
```

2. Update `core/variables/identity.tf` to define `pod_identity` variable structure with proper types and descriptions.

3. Update `core/variables/identity.auto.tfvars.tpl` with `REPLACE_POD_IDENTITY` token for dynamic substitution.

4. Update `scripts/configuration/identity-vars.sh` to extract `pod_identity` configuration from YAML and render into Terraform variables.

**Key Script Requirements:**
- Extract role definitions, policy templates, descriptions, and service account mappings
- Maintain idempotency across repeated runs
- Validate that template files exist before substitution

---

### TASK3: Create Pod Identity IAM Role and Associate Policies

**Objective:** Create the Load Balancer Controller IAM role with Pod Identity trust relationship and attach required permissions.

**Details:**

1. In `core/module/iam/cluster/identity/main.tf`, create the role using the updated principal format with `pods.eks.amazonaws.com` service principal.

2. In `core/module/iam/cluster/alb/main.tf`, create the policy and attachment resources:
   - Use `aws_iam_policy` to load the policy document from the template file
   - Use `aws_iam_role_policy_attachment` to attach the policy to the identified role

**Code Reference:**

```hcl
# core/module/iam/cluster/alb/main.tf
resource "aws_iam_policy" "kr_lbc_policy" {
  name        = local.policy.name
  description = local.policy.description
  policy      = file("${path.module}/../template/${local.policy.template_location}")
}

resource "aws_iam_role_policy_attachment" "kr_lbc_attach" {
  policy_arn = aws_iam_policy.kr_lbc_policy.arn
  role       = local.lbc_role.name
}
```

3. Update `core/module/iam/cluster/identity/output.tf` to expose:
   - `cluster_role_arns` – Map of role identifiers to role ARNs
   - `cluster_role_names` – Map of role identifiers to role names

4. Ensure role creation depends on identity module completion.

---

### TASK4: Create Service Account and Pod Identity Association

**Objective:** Link the IAM role to the Kubernetes service account for workload identity.

**Details:**

1. In `core/module/hosting/k8/namespace/main.tf` (or new service account module), create the service account:

```hcl
resource "kubernetes_service_account" "kr_lbc_sa" {
  metadata {
    name      = var.service_account.name
    namespace = var.service_account.namespace
  }
}
```

2. In `core/module/iam/cluster/alb/main.tf`, create the Pod Identity association:

```hcl
resource "aws_eks_pod_identity_association" "kr_lbc_auth" {
  cluster_name       = var.cluster_name
  namespace          = var.service_account.namespace
  service_account    = var.service_account.name
  role_arn           = local.lbc_role.arn
}
```

3. Add dependencies to ensure resources are created in order:
   - Service account depends on cluster and provider readiness
   - Pod Identity association depends on both the service account and the IAM role

---

### TASK5: Provision EKS Pod Identity Add-on

**Objective:** Deploy the `eks-pod-identity-agent` add-on to the cluster for credential injection.

**Details:**

1. In `core/module/hosting/k8/addons/main.tf`, create an add-on resource for Pod Identity:

```hcl
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = var.cluster_name
  addon_name   = "eks-pod-identity-agent"
}
```

2. Create a generalized add-on module that accepts configuration-driven add-on definitions:
   - Add-on names should map to cluster components (e.g., `pod_identity.required: true` → `eks-pod-identity-agent`)
   - Support additional add-ons in future iterations by extending the configuration

3. Update `core/variables/k8hosting.tf` to define add-on inputs and outputs.

4. Update `core/main.tf` to invoke the add-on module conditionally based on cluster opt-in and component flags.

---

### TASK6: Deploy Helm Provider and Load Balancer Controller Release

**Objective:** Install the AWS Load Balancer Controller using Helm and wire Kubernetes provider authentication.

**Details:**

1. Update `core/versions.tf` with Helm provider:

```hcl
helm = {
  source  = "hashicorp/helm"
  version = "~> 2.10"
}
```

2. In `core/main.tf`, configure the Helm provider with Kubernetes cluster authentication (matching existing Kubernetes provider pattern):

```hcl
provider "helm" {
  kubernetes {
    host                   = var.eks_enabled ? data.aws_eks_cluster.kr_target[0].endpoint : ""
    cluster_ca_certificate = var.eks_enabled ? base64decode(data.aws_eks_cluster.kr_target[0].certificate_authority[0].data) : ""

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.kubernetes_cluster_name]
      env         = var.auth_mode == "local" ? { AWS_PROFILE = var.aws_profile } : {}
    }
  }
}
```

3. In `core/module/hosting/k8/alb/main.tf`, create the Helm release:

```hcl
resource "helm_release" "kr_load_balancer_controller" {
  name       = var.lbc.name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = var.lbc.namespace

  set = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = var.lbc.service_account.create
    },
    {
      name  = "serviceAccount.name"
      value = var.lbc.service_account.name
    }
  ]

  depends_on = [
    module.deploy-kr-eks-cluster,
    module.deploy-kr-eks-nodegroup,
    aws_eks_pod_identity_association.kr_lbc_auth
  ]
}
```

4. Update `environment/dev/hosting/k8surface.yml` to include Load Balancer Controller configuration under `lbc` section (see TASK6 environment config below).

5. Update `core/variables/k8hosting.tf` and `core/variables/k8hosting.auto.tfvars.tpl` with `lbc` variable definitions.

6. Update `scripts/configuration/k8hosting-vars.sh` to extract and render `lbc` configuration from YAML.

---

## Post-Implementation Review Checklist

This checklist reflects the implementation completed on 2026-06-11 and should be verified during testing.

### Code Structure & Contracts

- [x] **TASK1**: `core/module/iam/cluster/identity/main.tf` updated to:
  - [x] Accept principal arrays with `type` and `value` fields (`principals` list in variable type)
  - [x] Dynamic `principals` block iterates array — conditional account ID substitution for `type = "AWS"` only
  - [x] `lbc_roles_map` local added: scope filtering via `startswith(r.sid, "lbc-")` skips `adm-*` roles
  - [x] `cluster_identity_roles` variable type updated in both `core/variables/identity.tf` and `core/module/iam/cluster/identity/variable.tf`

- [x] **TASK2**: Pod Identity variable definitions added:
  - [x] `core/variables/identity.tf` — `pod_identity` variable with `required`, `cluster_name`, `roles[]` (role, role_name, description, policy[], service_account)
  - [x] `core/variables/identity.auto.tfvars.tpl` — `REPLACE_POD_IDENTITY` token appended
  - [x] `scripts/configuration/identity-vars.sh` — `_render_pod_identity()` function added; cross-references `cluster_identity[].roles[]` to resolve `role_name` from `sid`
  - [x] `scripts/configuration/identity-vars.sh` — `_render_cluster_identity_roles()` updated to emit `principals = [...]` list instead of `principal = "..."` string

- [x] **TASK3**: IAM role and policy resources created:
  - [x] `core/module/iam/cluster/identity/main.tf` — existing role creation uses updated dynamic `principals` block with Pod Identity trust (`pods.eks.amazonaws.com` service principal via YAML)
  - [x] `core/module/iam/cluster/identity/output.tf` — exports `cluster_role_arns` (name → ARN) and `cluster_role_names` (sid → name)
  - [x] `core/module/iam/cluster/alb/main.tf` — `aws_iam_policy.kr_lbc_policy` loads from `${path.module}/../template/<template_location>`
  - [x] `core/module/iam/cluster/alb/main.tf` — `aws_iam_role_policy_attachment.kr_lbc_attach` attaches policy to role
  - [x] `core/module/iam/cluster/alb/variable.tf` — `pod_identity` and `cluster_role_arns` inputs defined
  - [x] `core/module/iam/cluster/alb/output.tf` — exports `lbc_policy_arns` and `pod_identity_association_ids`

- [x] **TASK4**: Service account and Pod Identity association created:
  - [x] `core/module/hosting/k8/namespace/main.tf` — `kubernetes_service_account.kr_lbc_sa` resource added, keyed by `namespace/name`
  - [x] `core/module/hosting/k8/namespace/variable.tf` — `service_accounts` list variable added
  - [x] `core/module/iam/cluster/alb/main.tf` — `aws_eks_pod_identity_association.kr_lbc_auth` created per role, using `cluster_role_arns[role_name]`
  - [x] `core/main.tf` — `deploy-kr-eks-namespaces` passes `service_accounts` from `pod_identity.roles[].service_account`
  - [x] `core/main.tf` — `deploy-kr-iam-cluster-alb` depends on both `deploy-kr-iam-cluster-identity` and `deploy-kr-eks-namespaces`

- [x] **TASK5**: Pod Identity add-on provisioned:
  - [x] `core/module/hosting/k8/addons/main.tf` — `aws_eks_addon.pod_identity_agent` with `count = var.eks_enabled && var.pod_identity_required ? 1 : 0`
  - [x] `core/module/hosting/k8/addons/variable.tf` — `cluster_name`, `eks_enabled`, `pod_identity_required` inputs
  - [x] `core/module/hosting/k8/addons/output.tf` — `addon_arns` map output
  - [x] `core/main.tf` — `deploy-kr-eks-addons` module wired with `pod_identity_required = var.pod_identity.required`

- [x] **TASK6**: Helm provider and Load Balancer Controller release configured:
  - [x] `core/versions.tf` — Helm provider `hashicorp/helm ~> 2.10` already present
  - [x] `core/main.tf` — `provider "helm"` block with `kubernetes {}` block mirroring Kubernetes provider exec auth
  - [x] Helm provider exec block uses `AWS_PROFILE` for local, no env for GHA — matches existing Kubernetes provider pattern
  - [x] `core/module/hosting/k8/alb/main.tf` — `helm_release.kr_load_balancer_controller` with `aws.github.io/eks-charts` chart
  - [x] `core/module/hosting/k8/alb/variable.tf` — `eks_enabled`, `cluster_name`, `lbc` list inputs
  - [x] `core/module/hosting/k8/alb/output.tf` — `lbc_release_name` and `lbc_release_status` outputs
  - [x] `core/variables/k8hosting.tf` — `lbc` variable with `name`, `description`, `namespace`, `service_account` fields
  - [x] `core/variables/k8hosting.auto.tfvars.tpl` — `REPLACE_LBC` token added
  - [x] `scripts/configuration/k8hosting-vars.sh` — `_render_lbc()` function added
  - [x] `environment/dev/hosting/k8surface.yml` — `lbc` section already present with full configuration

### YAML Source & Variable Generation

- [x] `environment/dev/platform/identity.yml`:
  - [x] Contains `pod_identity` section under `cluster_identity[0]` with `required: true`
  - [x] Role entry: `role: "lbc-01"`, `policy.template_location: "loadbalancer.json"`, `policy.name: "kr-carevo-dev-lbc-pod-identity-policy"`
  - [x] Service account: `name: "kr-carevo-dev-lbc-sa"`, `namespace: "kube-system"`
  - [x] LBC role `kr-carevo-dev-cluster-lbc-role` has `Principal.type: "Service"`, `Principal.value: "pods.eks.amazonaws.com"`

- [x] `environment/dev/hosting/k8surface.yml`:
  - [x] Contains `lbc` array under `cluster[0]` with name, description, namespace, service_account
  - [x] `service_account.create: false` — service account managed by namespace module

- [x] `scripts/configuration/replace-vars.sh kr-carevo dev` runs successfully:
  - [x] `identity.auto.tfvars` generated with `pod_identity` block
  - [x] `k8hosting.auto.tfvars` generated with `lbc` block
  - [x] No REPLACE_ tokens remain after substitution

### Terraform Validation

- [ ] `terraform init` from `core/` resolves Helm provider without conflicts
- [ ] `terraform validate` from `core/` passes after var generation
- [ ] `terraform fmt -recursive` reports no formatting issues (already applied)
- [ ] Plan execution shows:
  - [ ] IAM role `kr-carevo-dev-cluster-lbc-role` created with Pod Identity trust policy
  - [ ] IAM policy `kr-carevo-dev-lbc-pod-identity-policy` created from `loadbalancer.json`
  - [ ] IAM role policy attachment links policy to role
  - [ ] `kubernetes_service_account` `kr-carevo-dev-lbc-sa` created in `kube-system`
  - [ ] `aws_eks_pod_identity_association` configured with correct cluster, namespace, service account
  - [ ] `aws_eks_addon` `eks-pod-identity-agent` provisioned
  - [ ] Helm provider initializes without errors
  - [ ] `helm_release` `kr-carevo-dev-lbc` created pointing to `aws-load-balancer-controller`
  - [ ] No unrelated resources planned for modification
  - [ ] No missing variable warnings

### Dependency & Auth Path Integrity

- [ ] Helm and Kubernetes provider exec auth uses `AWS_PROFILE` for local runner, no env for GHA
- [ ] No static credentials, secrets, or account IDs in any Terraform module code or generated vars
- [ ] Module dependency chain verified:
  - [ ] `deploy-kr-iam-cluster-identity` → `deploy-kr-iam-cluster-alb` (role ARN available for association)
  - [ ] `deploy-kr-eks-namespaces` → `deploy-kr-iam-cluster-alb` (service account exists before association)
  - [ ] `deploy-kr-eks-addons` → `deploy-kr-eks-alb` (pod identity agent running before LBC helm release)
- [ ] Existing module contracts unchanged: cluster, nodegroup, IAM, network module inputs/outputs unmodified

### Opt-In & Filtering

- [ ] `pod_identity.required = false` → no `aws_eks_addon`, no `aws_eks_pod_identity_association`, and no LBC resources created
- [ ] `eks_enabled = false` → all EKS, LBC, manifest, and addon resources skipped
- [ ] `lbc_roles_map` in identity module correctly skips `adm-*` roles, processes `lbc-*` roles only

### Testing Execution (To be performed after code review)

**Prerequisite:** All above checklist items verified.

- [ ] Run `./scripts/runner.sh dev plan kr-carevo` and confirm:
  - [ ] Terraform plan completes without errors
  - [ ] All new resources appear in plan as expected
  - [ ] No regressions in existing cluster, nodegroup, IAM, or network resources
  - [ ] No authentication errors or missing variable warnings

- [ ] Inspect generated `core/variables/identity.auto.tfvars`:
  - [ ] `pod_identity` block present with correct `required`, `cluster_name`, `roles`
  - [ ] `cluster_identity_roles` uses `principals = [...]` list format (not `principal = "..."`)
  - [ ] `role_name` in pod_identity roles resolves to `kr-carevo-dev-cluster-lbc-role`

- [ ] Inspect generated `core/variables/k8hosting.auto.tfvars`:
  - [ ] `lbc` block present with correct name, namespace, service_account

- [ ] Optional: Apply infrastructure (if test environment available):
  - [ ] Pod Identity role and policy created in IAM
  - [ ] Service account `kr-carevo-dev-lbc-sa` created in `kube-system`
  - [ ] Pod Identity association active and functional
  - [ ] Add-on `eks-pod-identity-agent` running in `kube-system`
  - [ ] Load Balancer Controller pods running with Pod Identity authentication
