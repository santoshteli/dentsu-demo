output "role_arn" {
  description = "IRSA role used by the controller's service account."
  value       = aws_iam_role.this.arn
}

output "policy_arn" {
  description = "IAM policy attached to the role."
  value       = aws_iam_policy.this.arn
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.this.name
}

output "chart_version" {
  description = "Installed chart version."
  value       = helm_release.this.version
}
