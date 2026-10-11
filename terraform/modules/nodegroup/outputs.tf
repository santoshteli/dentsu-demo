output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_role_arn" {
  description = "IAM role of the nodes."
  value       = aws_iam_role.node.arn
}

output "launch_template_id" {
  description = "Launch template used by the node group."
  value       = aws_launch_template.node.id
}
