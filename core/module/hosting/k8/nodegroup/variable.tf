# =============================================================================
# variable.tf — EKS NodeGroup Module
#
# Input variables for EKS nodegroup creation.
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
  description = "Feature flag to enable EKS nodegroup creation"
  type        = bool
  default     = false
}

variable "cluster_names" {
  description = "Map of cluster name to cluster object from cluster module"
  type        = map(any)
  default     = {}
}

variable "nodegroup_role_arns" {
  description = "Map of EKS nodegroup IAM role name to ARN from IAM module"
  type        = map(string)
  default     = {}
}

variable "launch_template_ids" {
  description = "Map of nodegroup identifier to launch template ID from launch template module"
  type        = map(string)
  default     = {}
}

variable "launch_template_latest_versions" {
  description = "Map of nodegroup identifier to latest launch template version from launch template module"
  type        = map(number)
  default     = {}
}

variable "subnet_details" {
  description = "List of subnet details including subnet ID, name, AZ from subnet module"
  type = list(object({
    key         = string
    subnet_id   = string
    name        = string
    cidr_block  = string
    type        = string
    az          = string
    vpc_id      = string
  }))
  default = []
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
