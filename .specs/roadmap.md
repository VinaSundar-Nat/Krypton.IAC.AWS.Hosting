# Krypton Platform Roadmap

## Project Code

**I2P (Idea to Production)**

## Mission Statement

Krypton AWS IAC is part of a wider platform initiative to move ideas to production with minimal delivery friction while preserving mandatory controls, governance, and security guardrails.

The objective is to provide a reliable, repeatable, and policy-aligned path from feature intent to deployed infrastructure.

## Platform Mission

Krypton development follows a fully Spec-Driven Development (SDD) model.

At a high level:

1. Tribes define and refine feature requirements.
2. Local agent fleets (running across user machines - Open claw / Nemo claw and internal networks) collaborate with tribes and cross-tribe teams to plan delivery.
3. Hosted specialized agents support domain-specific workflows and requirement validation.
4. Once specifications are finalized, implementation can begin with high autonomy - Harness Layer.

For greenfield initiatives, this model is expected to significantly reduce setup time by accelerating project scaffolding and hosting baseline provisioning.

Architecture references are published to GitHub after requirements and implementation patterns are finalized.

## Scope

Krypton IAC AWS Hosting is designed so AWS services, networking layers, and security controls can be provisioned from program and project requirements.

### Scope Characteristics

- Configuration-driven structure sourced from environment YAML.
- Standardized guardrails aligned with 12-factor application principles.
- Architecture and control alignment with the AWS Well-Architected Framework pillars.
- Support for agent-assisted operations through configuration documentation and `llms.txt` context files.

## Automation And Governance Direction

The platform roadmap targets end-to-end automation through agentic execution, while retaining human approvals at critical control points.

Current governance model includes:

- GitHub Actions pipelines with gated deployment controls.
- Code owner approval requirements before environment deployment.
- State-backed execution using S3-hosted Terraform state.

Release-hardening direction includes:

- Full state capture and availability in S3.
- State versioning for rollback and auditability.
- DynamoDB-backed locking support for safe parallel execution across tribes.

## Current Implementation Summary

### Repository Implementation (README)

The current implementation provides an AWS Infrastructure-as-Code hosting platform built on Terraform with two authenticated execution paths:

- Local execution via IAM Roles Anywhere (keyless, certificate-based trust).
- CI/CD execution via GitHub Actions OIDC and STS role assumption.

Key capabilities in place:

- Zone-oriented network architecture (`ect`, `ict`, `rst`) mapped to distinct subnet and security boundaries.
- Provisioning and governance for VPC, subnetting, route tables, NAT/IGW, security groups, and NACL layers.
- Bootstrap path for trust anchor, certificate generation, role/profile setup, and runner enablement.
- Iteration-based SDD workflow under `.specs/iterations/` to align requirements, plans, and validations.

### EKS Implementation (EKSREADME)

The current EKS implementation is configuration-driven and focused on managed-mode deployment.

Implemented today:

- EKS managed node groups.
- ARM64 Graviton-based spot strategy for cost optimization.
- Multi-zone subnet association aligned to network tiers.
- Identity and access mapping through IAM roles, policies, and EKS access entries.
- YAML-to-Terraform variable flow for hosting and identity configuration.

Planned or partial areas:

- Self-managed nodes (future).
- AWS Fargate support (future).
- Karpenter-based autoscaling (planned; native ASG path currently used).

### Current Delivery Position

Krypton IAC AWS Hosting currently establishes a strong foundation for standardized, secure, and scalable environment provisioning, with clear progression toward higher autonomy, broader EKS operational patterns, and stricter multi-tribe execution controls.
