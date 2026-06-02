# Plan - Custom Namespace in Carevo Dev Clusters

## Objective

Implement configuration-driven Kubernetes namespace provisioning for opted-in EKS clusters in dev, using Terraform with authenticated Kubernetes provider wiring.

## Scope Alignment

- In scope: provider wiring, variable flow, namespace module implementation, and invocation sequencing.
- Out of scope: workload migration, RBAC/RoleBinding/Quota resource creation, non-dev rollout, and unrelated module refactors.

## Execution Plan

### Step 1 - Add Kubernetes Provider Version (TASK1)

- Update provider constraints in `core/versions.tf` to include `hashicorp/kubernetes` at `~> 2.20`.
- Keep existing provider blocks intact and avoid changing unrelated versions.

### Step 2 - Wire Namespace Inputs from YAML to Terraform Variables (TASK2)

- Extend variable definitions in `core/variables/k8hosting.tf` for namespace structures per cluster.
- Update generated var artifacts:
	- `core/variables/k8hosting.auto.tfvars`
	- `core/variables/k8hosting.auto.tfvars.tpl`
- Update extraction/replacement logic in `scripts/configuration/k8hosting-vars.sh`.
- Ensure values come from `environment/dev/hosting/k8surface.yml` only (no hardcoded namespace payloads).

### Step 3 - Implement Namespace Module Resources (TASK3)

- Implement namespace creation in `core/module/hosting/k8/namespace/main.tf`.
- Add or update corresponding input/output definitions in module variable and output files.
- Flatten nested inputs where needed into deterministic maps for `for_each`.
- Enforce dependency on cluster readiness before namespace creation.

### Step 4 - Expose Cluster Connectivity Outputs (TASK4)

- Update cluster outputs to expose:
	- decoded CA certificate (`certificate_authority[0].data` -> base64 decoded)
	- cluster endpoint
- Prefer direct values from `aws_eks_cluster`; if unavailable, add `data.aws_eks_cluster` fallback and output from data source.

### Step 5 - Configure Kubernetes Provider Authorization (TASK5)

- In `core/main.tf`, configure Kubernetes provider after cluster creation and with explicit dependency ordering.
- Bind cluster name, endpoint, and decoded CA per configured cluster from `environment/dev/hosting/k8surface.yml`.
- Use AWS EKS exec auth (`aws eks get-token`) compatible with both local runner and GHA paths.

### Step 6 - Invoke Namespace Module After Provider Readiness (TASK6)

- Invoke namespace module only after provider authorization path is in place.
- Pass required parameters (cluster key/name + namespace list/labels) from processed variables.
- Ensure non-opted-in clusters are excluded.

## Constraint Checks

### Must

- Namespace definitions are sourced from environment YAML.
- Namespace resources are created only after cluster and provider readiness.
- Standard labels are preserved and propagated.
- Auth works for both local and GHA execution.
- Endpoint and decoded CA are available for provider configuration.

### Must Not

- No namespace creation for non-opted-in clusters/components.
- No static credentials or sensitive values committed.
- No breaking changes to existing module contracts.
- No unrelated generated artifact changes.

## Validation Plan

- Regenerate vars via `scripts/configuration/replace-vars.sh <sid> dev` (or `scripts/runner.sh`).
- Run `terraform fmt -recursive` if formatting changes are introduced.
- Run `terraform validate` from `core/` after var generation.
- Run plan flow via `./scripts/runner.sh dev plan <sid>` and verify:
	- Kubernetes provider initializes successfully.
	- Namespace resources are planned only for opted-in clusters.
	- Labels are rendered as expected.

## Deliverables

- Updated Terraform provider configuration and namespace wiring.
- Updated variable extraction and var template flow for namespaces.
- Implemented namespace module and root invocation.
- Verified plan output with no regressions to existing cluster provisioning.
