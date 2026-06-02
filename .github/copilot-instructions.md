# GitHub Copilot Project Rules & Guidelines

This repository provisions AWS hosting infrastructure using Terraform, with environment-driven configuration rendered from YAML into tfvars.

## Core Development Philosophy
- Use Spec-Driven Development (SDD) for all feature work.
- Before making feature changes, inspect the latest folder under `.specs/iterations/`.
- If `plan.md` has actionable tasks, execute them in order.
- If iteration files are empty or incomplete, rely on existing repository behavior and request clarification before introducing new patterns.
- Prefer minimal, targeted changes over broad refactors.

## Project Setup Awareness

### Primary Stack
- IaC: Terraform (AWS provider)
- Languages: HCL, Bash, YAML
- Supporting tooling: `yq`, `aws`, `aws_signing_helper`, `terraform`, `kubectl` (for cluster checks)

### Key Directories
- `core/`: Terraform root module and child modules.
- `core/module/`: Domain modules for network, IAM, rules, and EKS hosting.
- `core/variables/`: Variable declarations and generated `*.auto.tfvars` files.
- `environment/<env>/`: Source-of-truth YAML by environment (`dev`, `stage`, `prod`).
- `scripts/configuration/`: YAML-to-tfvars generation scripts.
- `scripts/runner.sh`: Local Roles Anywhere Terraform execution entrypoint.
- `.specs/`: Iteration requirements and plans.

## Source Of Truth And Generation Rules
- Treat `environment/<env>/**/*.yml` as the source of truth for deployable configuration.
- Treat these files as generated artifacts unless task explicitly requires changing generation output:
	- `core/terraform.tfvars`
	- `core/variables/*.auto.tfvars`
- When configuration changes are needed, prefer editing:
	- `environment/org.yml`
	- `environment/<env>/platform/network.yml`
	- `environment/<env>/platform/rules.yml`
	- `environment/<env>/platform/identity.yml`
	- `environment/<env>/hosting/k8surface.yml`
	- `environment/<env>/zoning/*.yml|*.yaml`
- Regenerate vars through `scripts/configuration/replace-vars.sh <sid> <env>` (or `scripts/runner.sh`).
- Do not hardcode values in generated tfvars if the same value belongs in YAML inputs.

## Terraform Architecture Conventions
- Keep module boundaries clear and unchanged unless explicitly required:
	- Network: `core/module/network/*`
	- Rules (SG/NACL): `core/module/rules/*`
	- IAM: `core/module/iam/*`
	- EKS Hosting: `core/module/hosting/k8/*`
- Preserve input/output contracts between modules when possible.
- Follow existing naming/tagging patterns (`Environment`, `Program`, `Organization`, `ManagedBy`).
- Keep authentication mode behavior intact in `core/main.tf`:
	- `auth_mode="local"` uses Roles Anywhere profile via `runner.sh`.
	- `auth_mode="gha"` uses OIDC web identity role flow.

## EKS-Specific Notes
- EKS deployment is opt-in through `component[].opt-in` in `environment/<env>/hosting/k8surface.yml`.
- Keep `eks_enabled` wiring intact between YAML extraction scripts and Terraform variables.
- Respect existing managed-mode filtering (`mode == "managed"`) behavior.

## Shell Script Conventions
- Use `#!/usr/bin/env bash` and `set -euo pipefail` for new/edited scripts.
- Keep scripts idempotent where feasible.
- Validate required tools and input files early with clear error messages.
- Prefer safe quoting and avoid bashisms that break portability unless required by existing style.

## Validation Expectations
- For Terraform changes, run at minimum:
	- `terraform fmt -recursive` (when formatting is needed)
	- `terraform validate` from `core/` after var generation
- For script changes, run `shellcheck` when available.
- Prefer using existing workflow command:
	- `./scripts/runner.sh <env> plan <sid>`

## Documentation And Change Hygiene
- Update documentation (`README.md`, `EKSREADME.md`) when behavior or setup steps change.
- Keep comments concise and focused on non-obvious logic.
- Do not introduce secrets, credentials, account IDs, or private keys into tracked files.

## Safety Constraints
- Never use destructive git commands unless explicitly requested.
- Never revert unrelated user changes.
- If unexpected workspace modifications appear, pause and ask how to proceed.