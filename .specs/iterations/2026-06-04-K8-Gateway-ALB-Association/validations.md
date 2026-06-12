# Validations - EKS Pod Identity and ALB Gateway Association

## Validation Objective

Confirm that Pod Identity role architecture is correctly implemented, Load Balancer Controller is provisioned with secure workload identity, ALBs are created and associated with Kubernetes Gateways, and all configuration flows from YAML through Terraform variables to resource creation without hardcoded values or credential exposure.

## Preconditions

- Pod Identity role entries exist in `environment/dev/platform/identity.yml` under `pod_identity.roles`.
- LBC and Gateway configuration entries exist in `environment/dev/hosting/k8surface.yml` under `lbc` section.
- Cluster is opted in via `opt-in: true` in `environment/dev/hosting/k8surface.yml`.
- Required tooling is available: `terraform`, `yq`, `aws`, `helm`.
- Auth path is available for execution context (local runner or GHA).
- EKS cluster and nodegroups are already provisioned.

## Validation Matrix

### V1 - Extend IAM Principal Format (TASK1)

- Verify `core/module/iam/cluster/identity/main.tf` contains principal array iteration logic.
- Confirm account ID substitution applied only for `type = "AWS"` principals.
- Validate that role scope filtering processes `lbc-*` prefixed roles and skips `adm-*` prefixed roles.
- Verify existing admin role definitions remain unmodified.

Expected Result:

- Principal structure supports both Service and AWS types with correct substitution logic.
- Role scope filtering prevents unintended admin role modification.

### V2 - Pod Identity Variables and Variable Replacement (TASK2)

- Run var replacement flow using `scripts/configuration/replace-vars.sh kr-carevo dev`.
- Verify Pod Identity configuration is rendered in `core/variables/identity.auto.tfvars`.
- Confirm `scripts/configuration/identity-vars.sh` maps all pod_identity fields correctly (role, policy, service_account).
- Validate template file paths are resolved and substituted.
- Verify no hardcoded Pod Identity payloads appear in generated tfvars.

Expected Result:

- Generated vars reflect YAML Pod Identity definitions with proper role, policy, and service account mappings.

### V3 - Pod Identity IAM Role and Policy Resources (TASK3)

- Verify `core/module/iam/cluster/identity/main.tf` creates role with Pod Identity trust policy.
- Confirm role naming follows `kr-carevo-<env>-cluster-<component>-role` convention.
- Verify `core/module/iam/cluster/alb/main.tf` creates policy from template file.
- Confirm policy naming follows `kr-carevo-<env>-<component>-pod-identity-policy` convention.
- Validate `aws_iam_role_policy_attachment` links policy to role correctly.
- Verify `core/module/iam/cluster/identity/output.tf` exports `cluster_role_arns` and `cluster_role_names`.

Expected Result:

- IAM role created with Pod Identity trust relationship.
- Policy loaded from template and attached to role.
- Role identifier mappings available for downstream association.

### V4 - Service Account and Pod Identity Association (TASK4)

- Verify service account resource created in `kube-system` namespace with name `kr-carevo-dev-lbc-sa`.
- Confirm `aws_eks_pod_identity_association` resource links service account to Pod Identity role.
- Validate association cluster_name, namespace, and service_account match configuration.
- Verify resource dependency ensures service account created before association.
- Confirm Kubernetes provider readiness precedes service account creation.

Expected Result:

- Service account created in correct namespace with expected name.
- Pod Identity association configured with correct cluster, namespace, and service account references.

### V5 - EKS Pod Identity Add-on Provisioning (TASK5)

- Verify `core/module/hosting/k8/addons/main.tf` contains `aws_eks_addon` resource for `eks-pod-identity-agent`.
- Confirm add-on creation is conditional on cluster opt-in and `pod_identity.required: true`.
- Validate module design supports configuration-driven add-on definitions for future extensibility.
- Verify `core/variables/k8hosting.tf` defines add-on input variables.

Expected Result:

- Pod Identity add-on resource provisioned when opt-in enabled.
- Module architecture supports future add-on extensions without refactoring.

### V6 - Helm Provider and Load Balancer Controller Release (TASK6)

- Verify `core/versions.tf` includes Helm provider with version `~> 2.10`.
- Confirm `terraform init` resolves Helm provider without conflicts.
- Verify `core/main.tf` provider "helm" block configured with Kubernetes authentication.
- Validate Helm provider supports both local runner (AWS Roles Anywhere) and GHA (OIDC) auth paths.
- Verify `core/module/hosting/k8/alb/main.tf` contains `helm_release` resource for Load Balancer Controller.
- Confirm Helm release configured with:
	- Chart repository: `https://aws.github.io/eks-charts`
	- Chart name: `aws-load-balancer-controller`
	- Namespace: matches `lbc.namespace`
	- Service account: matches `lbc.service_account` configuration
- Validate Helm release depends on cluster, nodegroup, and Pod Identity association.
- Verify `environment/dev/hosting/k8surface.yml` includes `lbc` section with name, namespace, and service account.
- Confirm `core/variables/k8hosting.tf` defines `lbc` input variable with proper type.
- Verify `scripts/configuration/k8hosting-vars.sh` extracts and renders LBC configuration from YAML.

Expected Result:

- Helm provider initialized successfully.
- Load Balancer Controller Helm release created with secure workload identity configuration.
- LBC deployment precedes Gateway manifest creation.

### V7 - Gateway Class and Gateway Manifests (TASK7)

- Verify Gateway Class resource exists in `core/module/hosting/k8/manifests/main.tf`.
- Confirm Gateway Class configured with:
	- apiVersion: `gateway.networking.k8s.io/v1`
	- kind: `GatewayClass`
	- spec.controllerName: `gateway.k8s.aws/alb`
- Verify generic Gateway resource implemented with `for_each` loop over gateway array.
- Confirm Gateway resources include:
	- Correct metadata (name, namespace, annotations)
	- gatewayClassName matching Gateway Class name
	- Listener configuration from ports array
	- allowedRoutes namespace selectors from matches array
- Validate Gateway resources depend on Load Balancer Controller readiness.
- Verify `environment/dev/hosting/k8surface.yml` includes `gateway_manifests` section with `gc_name` and `gateway` array.
- Confirm gateway array includes both public and private ALB gateways with proper annotations and selector configuration.
- Verify `core/variables/k8hosting.tf` defines `gateway_manifests` input variable.
- Confirm `scripts/configuration/k8hosting-vars.sh` extracts Gateway configuration from YAML.

Expected Result:

- Gateway Class created as ALB controller integration point.
- Both public and private Gateway resources created with correct listener and selector configurations.
- Gateway Class and Gateways provisioned in correct dependency order.

## Constraint Validation

### Must

- Pod Identity configuration sourced from `environment/dev/platform/identity.yml`.
- Trust policy principals support Service and AWS types with conditional account ID substitution.
- IAM policies loaded from `core/module/iam/template/` files, not hardcoded.
- LBC and Gateway configuration sourced from `environment/dev/hosting/k8surface.yml`.
- Role association matches role identifiers across identity and hosting configurations.
- All Pod Identity, LBC, and Gateway resources created conditionally based on cluster opt-in.
- Helm and Kubernetes provider authentication supports both local and GHA execution paths.
- Service account and Pod Identity association in correct order with proper dependencies.
- Gateway resources depend on Load Balancer Controller readiness.

### Must Not

- No Pod Identity resources created for non-opted-in clusters.
- No hardcoded account IDs, cluster names, or environment values in Terraform modules.
- No static credentials or sensitive data in code or generated vars.
- No Pod Identity association bypass (all workloads authenticate via assumed roles).
- No ALB or Gateway creation without corresponding network and security group rules.
- No breaking changes to existing cluster, nodegroup, IAM, or network module interfaces.
- No HTTP Routes, Ingress resources, or application onboarding in this iteration.

### Out of Scope Verification

- Confirm this iteration does not include:
	- HTTPRoute or HTTPRuleGroup resource definitions
	- Application traffic routing configuration
	- Production or staging environment rollout
	- Unrelated cluster provisioning refactors
	- RBAC policies or service account usage rules
	- Load Balancer Controller troubleshooting or operational procedures

## Execution Commands

```bash
# 1) Regenerate vars for all features
./scripts/configuration/replace-vars.sh kr-carevo dev

# 2) Validate formatting
terraform fmt -recursive

# 3) Validate Terraform syntax
cd core && terraform validate

# 4) Dry-run plan through project runner
./scripts/runner.sh dev plan kr-carevo

# 5) Inspect generated identity vars
cat ./core/variables/identity.auto.tfvars | grep -A 20 "pod_identity"

# 6) Inspect generated k8hosting vars
cat ./core/variables/k8hosting.auto.tfvars | grep -A 50 "lbc"
```

## Acceptance Criteria

- Terraform plan succeeds without provider/auth errors or variable warnings.
- IAM role created with Pod Identity trust policy containing correct principals.
- IAM policy loaded from template and attached to role.
- Service account created in `kube-system` namespace.
- Pod Identity association configured with correct cluster, namespace, and service account.
- Add-on `eks-pod-identity-agent` provisioned and marked for creation.
- Helm provider initializes successfully and connected to cluster.
- Load Balancer Controller Helm release created with service account configuration.
- Gateway Class resource created as ALB controller integration point.
- Gateway resources created for both public and private ALBs with correct listener and selector configurations.
- All resources rendered from environment YAML configuration (no hardcoded values in Terraform).
- No regressions in existing cluster, nodegroup, IAM, or network resource provisioning.
- No static credentials or sensitive data appearing in plan output or generated vars.
- Cluster opt-in filtering correctly excludes non-opted-in clusters from all Pod Identity, LBC, and Gateway resources.
