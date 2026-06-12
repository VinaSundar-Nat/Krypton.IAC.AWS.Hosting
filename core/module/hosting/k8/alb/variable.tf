# =============================================================================
# variable.tf — EKS ALB / Load Balancer Controller Module
#
# Input variables for the AWS Load Balancer Controller Helm release.
# Sourced from k8surface.yml component.cluster[].lbc[].
# =============================================================================

variable "eks_enabled" {
  description = "Feature flag — skip LBC provisioning when EKS is not opted in."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "EKS cluster name for the Load Balancer Controller to manage."
  type        = string
  default     = ""
}

variable "lbc" {
  description = <<-EOT
    Load Balancer Controller configuration sourced from k8surface.yml component.cluster[].lbc[].
    name            - Helm release name.
    description     - Human-readable description.
    namespace       - Target Kubernetes namespace for the Helm release.
    service_account - Service account name and create flag.
  EOT
  type = list(object({
    name        = string
    description = string
    namespace   = string
    service_account = object({
      name   = string
      create = bool
    })
  }))
  default = []
}

variable "aws_region" {
  description = "Target AWS region for the Load Balancer Controller."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID where the Load Balancer Controller will operate."
  type        = string
  default     = ""
}
