# Networking Module Outputs

output "vpc_id" {
  description = "VPC ID"
  value       = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = var.create_vpc ? aws_subnet.public[*].id : []
}

output "security_group_id" {
  description = "Security group ID for gateway"
  value       = aws_security_group.gateway.id
}

output "security_group_name" {
  description = "Security group name for gateway"
  value       = aws_security_group.gateway.name
}
