output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets. Only available once they have a route to the NAT gateway."
  value       = aws_subnet.private[*].id

  # Anything placed in these subnets (the Jenkins host, EKS nodes) needs
  # internet access at boot, so make consumers wait for the NAT route.
  depends_on = [aws_route.private_nat, aws_route_table_association.private]
}

output "nat_gateway_public_ip" {
  description = "Public IP that all outbound traffic from the private subnets uses."
  value       = aws_eip.nat.public_ip
}
