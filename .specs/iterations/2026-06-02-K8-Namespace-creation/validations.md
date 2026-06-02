# Validations - Custom Namespace in Carevo Dev Clusters

## Validation Objective

Confirm that namespace provisioning is configuration-driven, cluster-scoped, and safely authorized through Terraform for opted-in dev EKS clusters.

## Preconditions

- Namespace entries exist in `environment/dev/hosting/k8surface.yml` under relevant cluster definitions.
- Required tooling is available: `terraform`, `yq`, `aws`.
- Auth path is available for execution context (local runner or GHA).

## Validation Matrix

### V1 - Provider Version Registration (TASK1)

- Verify `core/versions.tf` contains provider `hashicorp/kubernetes` with version `~> 2.20`.
- Confirm `terraform init` resolves provider without conflicts.

Expected Result:

- Kubernetes provider is downloaded and lock resolution succeeds.

### V2 - Variable Flow from YAML to tfvars (TASK2)

- Run var replacement flow using `scripts/configuration/replace-vars.sh <sid> dev`.
- Verify namespace-related values are rendered in:
	- `core/variables/k8hosting.auto.tfvars`
	- `core/variables/k8hosting.auto.tfvars.tpl`
- Verify `scripts/configuration/k8hosting-vars.sh` maps namespace fields correctly (name, description, labels).

Expected Result:

- Generated vars reflect YAML namespace definitions with no hardcoded namespace payloads in module logic.

### V3 - Namespace Module Resource Logic (TASK3)

- Verify namespace resources exist in `core/module/hosting/k8/namespace/main.tf`.
- Confirm module variables/outputs support namespace input structures.
- Confirm `for_each` input is deterministic and supports multiple namespaces per cluster.
- Confirm cluster readiness dependency is enforced.

Expected Result:

- Terraform plan shows namespace resources only for defined namespaces and no dependency cycle errors.

### V4 - Cluster Output Availability (TASK4)

- Verify cluster module outputs expose:
	- decoded CA data
	- cluster endpoint
- If data source fallback is implemented, validate values match cluster state.

Expected Result:

- Provider-required connectivity values are available for all target clusters.

### V5 - Kubernetes Provider Authorization (TASK5)

- Verify `core/main.tf` provider config references cluster endpoint, decoded CA cert, and cluster name.
- Confirm exec auth uses `aws eks get-token --cluster-name <name>`.
- Validate plan execution in both contexts where possible:
	- local runner flow
	- GHA-compatible flow assumptions

Expected Result:

- Provider initializes successfully and token-based auth works without static credentials.

### V6 - Namespace Module Invocation Ordering (TASK6)

- Verify namespace module invocation occurs after provider/cluster readiness.
- Verify module input filtering excludes non-opted-in clusters/components.

Expected Result:

- Plan includes namespace creation only for opted-in targets and no unexpected namespace resources.

## Constraint Validation

### Must

- Namespaces are sourced from environment YAML.
- Namespace creation happens post cluster and provider readiness.
- Governance labels are applied consistently.
- Both local and GHA auth paths remain compatible.
- Endpoint and decoded CA outputs are present and consumed.

### Must Not

- No non-opted-in cluster namespace creation.
- No static credential introduction.
- No module contract breakage across existing interfaces.
- No unrelated generated artifact modifications.

### Out of Scope Verification

- Confirm this iteration does not include:
	- workload migration into namespaces
	- RBAC/RoleBinding/Quota resources
	- non-dev environment rollout
	- unrelated cluster provisioning redesign

## Execution Commands

```bash
# 1) Regenerate vars
scripts/configuration/replace-vars.sh <sid> dev

# 2) Validate formatting if required
terraform fmt -recursive

# 3) Validate Terraform
cd core && terraform validate

# 4) Dry-run plan through project runner
./scripts/runner.sh dev plan <sid>
```

## Acceptance Criteria

- Terraform plan succeeds without provider/auth errors.
- Namespace resources are generated only for configured, opted-in targets.
- Labels from YAML are preserved in planned namespace metadata.
- No regressions in existing cluster provisioning behavior.
