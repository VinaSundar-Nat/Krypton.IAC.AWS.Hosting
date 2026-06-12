# =============================================================================
# output.tf — EKS ALB / Load Balancer Controller Module
# =============================================================================

output "lbc_release_name" {
  description = "Name of the deployed Load Balancer Controller Helm release."
  value       = length(helm_release.kr_load_balancer_controller) > 0 ? helm_release.kr_load_balancer_controller[0].name : ""
}

output "lbc_release_status" {
  description = "Status of the deployed Load Balancer Controller Helm release."
  value       = length(helm_release.kr_load_balancer_controller) > 0 ? helm_release.kr_load_balancer_controller[0].status : ""
}
