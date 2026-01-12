# Compute Module Outputs

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.gateway.id
}

output "instance_private_ip" {
  description = "Private IP address"
  value       = aws_instance.gateway.private_ip
}

output "instance_public_ip" {
  description = "Public IP address"
  value       = aws_instance.gateway.public_ip
}

output "elastic_ip" {
  description = "Elastic IP address (if allocated)"
  value       = var.allocate_eip ? aws_eip.gateway[0].public_ip : null
}

output "iam_role_name" {
  description = "IAM role name"
  value       = aws_iam_role.gateway.name
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.gateway.arn
}
