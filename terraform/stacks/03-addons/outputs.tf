output "alb_controller_role_arn" {
  description = "IRSA role of the controller's service account."
  value       = module.alb_controller.role_arn
}

output "alb_controller_policy_arn" {
  description = "IAM policy of the controller."
  value       = module.alb_controller.policy_arn
}

output "alb_controller_chart_version" {
  description = "Installed Helm chart version."
  value       = module.alb_controller.chart_version
}

output "verify_commands" {
  description = "Check the controller from the Jenkins host."
  value       = "kubectl -n kube-system get deploy aws-load-balancer-controller && kubectl get ingressclass alb"
}
