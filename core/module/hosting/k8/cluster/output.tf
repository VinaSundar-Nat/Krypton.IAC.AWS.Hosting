# =============================================================================
# output.tf — EKS Cluster Module
# =============================================================================

output "cluster_ids" {
  description = "Map of EKS cluster name to cluster ID"
  value = {
    for name, cluster in aws_eks_cluster.kr_cluster : name => cluster.id
  }
}

output "cluster_arns" {
  description = "Map of EKS cluster name to cluster ARN"
  value = {
    for name, cluster in aws_eks_cluster.kr_cluster : name => cluster.arn
  }
}

output "cluster_names" {
  description = "List of created EKS cluster names"
  value = [
    for name, cluster in aws_eks_cluster.kr_cluster : cluster.name
  ]
}

output "cluster_endpoints" {
  description = "Map of EKS cluster name to endpoint"
  value = {
    for name, cluster in aws_eks_cluster.kr_cluster : name => cluster.endpoint
  }
}

output "cluster_certificate_authority" {
  description = "Map of EKS cluster name to certificate authority data"
  value = {
    for name, cluster in aws_eks_cluster.kr_cluster : name => cluster.certificate_authority[0].data
  }
  sensitive = true
}

output "clusters" {
  description = "Complete EKS cluster objects"
  value       = aws_eks_cluster.kr_cluster
  sensitive   = true
}

output "cluster_security_group_ids" {
  description = "Map of EKS cluster name to the auto-created cluster security group ID"
  value = {
    for name, cluster in aws_eks_cluster.kr_cluster :
    name => cluster.vpc_config[0].cluster_security_group_id
  }
}
