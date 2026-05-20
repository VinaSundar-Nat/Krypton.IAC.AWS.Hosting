# =============================================================================
# variable.tf — EKS Launch Template Module
#
# Input variables for EKS launch template creation.
# =============================================================================

variable "eks_clusters" {
  description = "List of EKS cluster definitions from k8surface.yml"
  type = list(object({
    name                    = string
    mode                    = string
    role                    = string
    version                 = string
    subnets                 = list(string)
    security_groups         = list(string)
    endpoint_public_access  = bool
    endpoint_private_access = bool
    nodegroups              = list(object({
      name        = string
      description = string
      role        = string
      template    = string
      subnets     = list(string)
      template_parameters = object({
        name                  = string
        name_prefix           = string
        description           = string
        security_groups       = list(string)
        block_device_mappings = object({
          device_name           = string
          type                  = string
          volume_size           = number
          volume_type           = string
          delete_on_termination = bool
          encrypted             = bool
        })
        monitoring = object({
          enabled = bool
        })
        lifecycle = object({
          create_before_destroy = bool
        })
        tags = map(string)
      })
      machine = object({
        instance_types = list(string)
        ami_type       = string
        capacity_type  = string
      })
      scaling_config = object({
        desired_size = number
        max_size     = number
        min_size     = number
      })
    }))
  }))
  default = []
}

variable "eks_enabled" {
  description = "Feature flag to enable EKS launch template creation"
  type        = bool
  default     = false
}

variable "security_group_ids" {
  description = "Map of security group logical id reference to AWS security group resource ID"
  type        = map(string)
  default     = {}
}

variable "cluster_security_group_ids" {
  description = "Map of EKS cluster name to the auto-created cluster security group ID (required so nodes can join the control plane)"
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
