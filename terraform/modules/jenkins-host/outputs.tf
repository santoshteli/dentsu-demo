output "instance_id" {
  description = "Instance ID, used as the SSM session target."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP of the host."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Security group of the host. Stack 02-eks allows 443 from it to the cluster."
  value       = aws_security_group.this.id
}

output "role_arn" {
  description = "IAM role of the host. Stack 02-eks gives it an EKS access entry."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the host's IAM role."
  value       = aws_iam_role.this.name
}

output "alb_url" {
  description = "Jenkins URL through the ALB, or null when the ALB is disabled."
  value       = var.enable_public_alb ? "http://${aws_lb.jenkins[0].dns_name}" : null
}

output "alb_security_group_id" {
  description = "Security group of the Jenkins ALB. Add the client IP here to open access."
  value       = var.enable_public_alb ? aws_security_group.alb[0].id : null
}
