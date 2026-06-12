# Plan - EKS Pod Identity and ALB Gateway Association

## Objective

Implement secure workload identity through EKS Pod Identity for the AWS Load Balancer Controller add-on, provision ALB resources, and associate them with Kubernetes Gateways for traffic routing across public and private subnets in dev environment.

## Scope Alignment

- In scope: Pod Identity IAM role/policy architecture, service account and Pod Identity association, Load Balancer Controller provisioning via Helm, Gateway Class and Gateway manifests, variable flow from YAML to Terraform, and provider wiring for Helm and Kubernetes resources.
- Out of scope: HTTPRoute/HTTPRuleGroup implementation, application onboarding and traffic routing configuration, non-dev environment rollout, unrelated cluster/nodegroup/network refactors, RBAC policies for service accounts, and Load Balancer Controller operational runbooks.

## Execution Plan

### Step 1 - Extend IAM Principal Format for Pod Identity (TASK1)

- Update `core/module/iam/cluster/identity/main.tf` to accept principals as array of objects with `type` and `value` fields.
- Implement account ID substitution logic for `type = "AWS"` principals only.
- Apply scope filtering to process only `lbc-*` prefixed roles and skip `adm-*` prefixed roles.
- Preserve existing admin role definitions without modification.

### Step 2 - Define Pod Identity Variables and Wire Variable Replacement (TASK2)

- Extend variable definitions in `core/variables/identity.tf` to include `pod_identity` structure with role, policy, description, and service account mappings.
- Update generated var artifacts:
	- `core/variables/identity.auto.tfvars`
	- `core/variables/identity.auto.tfvars.tpl`
- Update extraction/replacement logic in `scripts/configuration/identity-vars.sh` to extract Pod Identity configuration from YAML.
- Ensure values come from `environment/dev/platform/identity.yml` only (no hardcoded Pod Identity definitions).

### Step 3 - Create Pod Identity IAM Role and Associate Policies (TASK3)

- Implement role creation in `core/module/iam/cluster/identity/main.tf` with Pod Identity trust policy.
- Implement policy creation and attachment in `core/module/iam/cluster/alb/main.tf` using template files.
- Update `core/module/iam/cluster/identity/output.tf` to expose `cluster_role_arns` and `cluster_role_names` maps.
- Ensure role naming follows `kr-carevo-<env>-cluster-<component>-role` convention.

### Step 4 - Create Service Account and Pod Identity Association (TASK4)

- Implement service account creation for Load Balancer Controller in `core/module/hosting/k8/namespace/main.tf` or dedicated service account module.
- Implement `aws_eks_pod_identity_association` resource in `core/module/iam/cluster/alb/main.tf` to link role to service account.
- Enforce dependency ordering: service account → Pod Identity association.
- Ensure Kubernetes provider is ready before service account creation.

### Step 5 - Provision EKS Pod Identity Add-on (TASK5)

- Implement `aws_eks_addon` resource in `core/module/hosting/k8/addons/main.tf` for `eks-pod-identity-agent`.
- Design generalized add-on module to support configuration-driven add-on definitions.
- Map `pod_identity.required: true` to `eks-pod-identity-agent` add-on creation.
- Update `core/variables/k8hosting.tf` to define add-on input variables.
- Ensure add-on creation depends on cluster readiness and is conditional on opt-in.

### Step 6 - Deploy Helm Provider and Load Balancer Controller Release (TASK6)

- Update `core/versions.tf` to include Helm provider version `~> 2.10`.
- Configure Helm provider in `core/main.tf` with Kubernetes cluster authentication (matching existing Kubernetes provider pattern).
- Support both local runner (AWS Roles Anywhere) and GHA (OIDC) auth paths.
- Implement Helm release resource in `core/module/hosting/k8/alb/main.tf` for AWS Load Balancer Controller.
- Update `environment/dev/hosting/k8surface.yml` to include `lbc` configuration section.
- Update `core/variables/k8hosting.tf` and template files to define LBC variables.
- Update `scripts/configuration/k8hosting-vars.sh` to extract and render LBC configuration from YAML.

### Step 7 - Create Gateway Class and Gateway Manifests (TASK7)

- Implement Gateway Class resource in `core/module/hosting/k8/manifests/main.tf` with ALB controller reference.
- Implement generic Gateway resource that renders from configuration using `for_each` loop.
- Map gateway ports and allowedRoutes namespace selectors from configuration.
- Ensure Gateway resources depend on Load Balancer Controller readiness.
- Update `environment/dev/hosting/k8surface.yml` to include `gateway_manifests` section under `lbc`.
- Update `core/variables/k8hosting.tf` to define `gateway_manifests` input variable.
- Update `scripts/configuration/k8hosting-vars.sh` to extract Gateway configuration from YAML.

## Constraint Checks

### Must

- Pod Identity role definitions sourced from `environment/dev/platform/identity.yml`.
- Trust policy principals support both Service and AWS types with conditional account ID substitution.
- IAM policies loaded from templates, not hardcoded.
- Pod Identity, LBC, and Gateway configuration driven by environment YAML.
- Role association logic matches role identifiers across identity and hosting configurations.
- All resources created conditionally based on cluster opt-in status.
- Helm and Kubernetes provider support both local and GHA authentication paths.
- Gateway manifests depend on Load Balancer Controller readiness.

### Must Not

- No Pod Identity resources created for non-opted-in clusters.
- No hardcoded account IDs, cluster names, or environment values in Terraform modules.
- No static credentials or sensitive data in code or generated vars.
- No Pod Identity association bypass; workloads must use assumed roles.
- No ALB/Gateway creation without proper network and security rules.
- No breaking changes to existing IAM, network, or cluster module contracts.
- No HTTP Routes or Ingress resources in this iteration.

## Validation Plan

- Regenerate vars via `scripts/configuration/replace-vars.sh kr-carevo dev` and verify Pod Identity, LBC, and Gateway configuration rendered correctly.
- Run `terraform fmt -recursive` if formatting changes are introduced.
- Run `terraform validate` from `core/` after var generation.
- Run plan flow via `./scripts/runner.sh dev plan kr-carevo` and verify:
	- IAM role created with Pod Identity trust policy.
	- IAM policy created and attached to role.
	- Service account created in `kube-system` namespace.
	- Pod Identity association configured.
	- Add-on `eks-pod-identity-agent` provisioned.
	- Helm provider initializes successfully.
	- Load Balancer Controller Helm release created with correct service account configuration.
	- Gateway Class and Gateway manifests created with proper listener and selector configurations.
	- No authentication errors or missing variable warnings.
	- No regressions in existing cluster, nodegroup, IAM, or network resources.

## Deliverables

- Extended IAM principal format supporting type/value structure with conditional account ID substitution.
- Pod Identity variable definitions and YAML-to-Terraform variable extraction pipeline.
- IAM role, policy, and attachment resources for Load Balancer Controller.
- Service account and Pod Identity association resources.
- EKS Pod Identity add-on provisioning with configuration-driven design.
- Helm provider configuration and Load Balancer Controller Helm release.
- Gateway Class and Gateway manifest resources with configuration-driven rendering.
- Updated YAML source files with Pod Identity, LBC, and Gateway definitions.
- Updated variable extraction scripts with Pod Identity, LBC, and Gateway configuration handling.
- Verified plan output with no regressions to existing infrastructure provisioning.
