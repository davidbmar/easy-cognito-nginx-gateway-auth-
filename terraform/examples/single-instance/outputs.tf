# Single Instance Example Outputs

output "gateway_url" {
  description = "Gateway URL"
  value       = "https://${var.domain_name}"
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = module.compute.instance_id
}

output "public_ip" {
  description = "Public IP address"
  value       = var.allocate_eip ? module.compute.elastic_ip : module.compute.instance_public_ip
}

output "security_group_id" {
  description = "Security group ID (use with ssh-helper)"
  value       = module.networking.security_group_id
}

output "security_group_name" {
  description = "Security group name"
  value       = module.networking.security_group_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "next_steps" {
  description = "Next steps to complete setup"
  value       = <<-EOT

    ✅ Infrastructure deployed successfully!

    Next steps:

    1. Update DNS:
       - Point ${var.domain_name} to ${var.allocate_eip ? module.compute.elastic_ip : module.compute.instance_public_ip}
       - Create A record in your DNS provider

    2. Wait for installation (5-10 minutes):
       - Check logs: ssh ubuntu@${var.allocate_eip ? module.compute.elastic_ip : module.compute.instance_public_ip}
       - View: sudo tail -f /var/log/user-data.log

    3. Test authentication:
       - Visit: https://${var.domain_name}
       - You'll be redirected to Cognito login

    4. Configure SSH access (optional):
       - Install ssh-helper: git clone <ssh-helper-repo>
       - Configure: echo "security_group_id: ${module.networking.security_group_id}" > config.yml
       - Add your IP: ./ssh-helper.py add --duration=24h

    5. Deploy applications:
       - Add nginx location blocks for your apps
       - Example: /cloner/ → website-cloner on port 3000

    Troubleshooting:
    - Installation logs: /var/log/user-data.log
    - nginx logs: /var/log/nginx/error.log
    - oauth2-proxy logs: sudo journalctl -u oauth2-proxy
  EOT
}
