output "repository_name" {
  description = "Name of the ECR repository."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "URL used for docker push and in the Kubernetes deployment image."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository, used to scope push permissions."
  value       = aws_ecr_repository.this.arn
}
