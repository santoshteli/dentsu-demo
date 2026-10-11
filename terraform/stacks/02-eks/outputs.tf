output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_version" {
  description = "Kubernetes version of the control plane."
  value       = module.eks.cluster_version
}

output "cluster_endpoint" {
  description = "Private API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA certificate of the API server. Used by the Helm provider in stack 03-addons."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Cluster security group."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN. Stack 03-addons trusts it in the IRSA role."
  value       = module.eks.oidc_provider_arn
}

output "oidc_issuer" {
  description = "OIDC issuer without https://. Stack 03-addons uses it in IRSA conditions."
  value       = module.eks.oidc_issuer
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = module.nodegroup.node_group_name
}

output "node_role_arn" {
  description = "IAM role of the nodes."
  value       = module.nodegroup.node_role_arn
}

output "update_kubeconfig_command" {
  description = "Configure kubectl on the Jenkins host."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
