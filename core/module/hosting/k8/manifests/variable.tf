# =============================================================================
# variable.tf — EKS Manifests Module
#
# Input variables for Kubernetes Gateway Class and Gateway resource provisioning.
# Sourced from k8surface.yml component.cluster[].lbc[].gateway_manifests.
# =============================================================================

variable "eks_enabled" {
  description = "Feature flag — skip manifest provisioning when EKS is not opted in."
  type        = bool
  default     = false
}

variable "gateway_manifests" {
  description = <<-EOT
    Gateway Class and Gateway resource configuration.
    gc_name  - GatewayClass resource name (ALB controller integration point).
    gateway  - List of Gateway resource definitions with listeners and namespace selectors.
  EOT
  type = object({
    gc_name = string
    gateway = list(object({
      name          = string
      gateway_class = string
      description   = string
      namespace     = string
      annotations   = map(string)
      ports = list(object({
        name     = string
        port     = number
        protocol = string
      }))
      matches = list(object({
        name  = string
        value = bool
      }))
    }))
  })
  default = {
    gc_name = ""
    gateway = []
  }
}
