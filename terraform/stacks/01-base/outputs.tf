output "region" {
  description = "AWS region."
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID. Used by stacks 02-eks and 03-addons."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes and pods)."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_public_ip" {
  description = "Egress IP of the private subnets."
  value       = module.vpc.nat_gateway_public_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL for the application image."
  value       = module.ecr.repository_url
}

output "jenkins_instance_id" {
  description = "Jenkins host instance ID."
  value       = module.jenkins_host.instance_id
}

output "jenkins_security_group_id" {
  description = "Jenkins host security group. Stack 02-eks allows 443 from it."
  value       = module.jenkins_host.security_group_id
}

output "jenkins_role_arn" {
  description = "Jenkins host IAM role. Stack 02-eks gives it an EKS access entry."
  value       = module.jenkins_host.role_arn
}

output "jenkins_url" {
  description = "Jenkins through the ALB. Reachable only after an inbound rule for your IP is added to jenkins_alb_security_group_id."
  value       = module.jenkins_host.alb_url
}

output "jenkins_alb_security_group_id" {
  description = "Security group to edit (HTTP, Source: My IP) to open Jenkins for the current client."
  value       = module.jenkins_host.alb_security_group_id
}

output "ssm_shell_command" {
  description = "Open a shell on the Jenkins host."
  value       = "aws ssm start-session --region ${var.region} --target ${module.jenkins_host.instance_id}"
}

output "ssm_jenkins_port_forward_command" {
  description = "Forward Jenkins to http://localhost:8080 on the laptop."
  value       = "aws ssm start-session --region ${var.region} --target ${module.jenkins_host.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"8080\"]}'"
}
