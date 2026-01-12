# Single Instance Example Variables

# Required Variables
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain name for the gateway (e.g., gateway.example.com)"
  type        = string
}

variable "cognito_pool_id" {
  description = "Cognito User Pool ID (e.g., us-east-1_XXXXXXXXX)"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito App Client ID"
  type        = string
}

variable "cognito_client_secret" {
  description = "Cognito App Client Secret"
  type        = string
  sensitive   = true
}

# Optional - Naming
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

# Optional - Networking
variable "create_vpc" {
  description = "Create new VPC (true) or use existing (false)"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "Existing VPC ID (if create_vpc = false)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for new VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access HTTPS"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks for SSH (use ssh-helper for dynamic IPs)"
  type        = list(string)
  default     = []
}

# Optional - Compute
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "EC2 key pair name for SSH"
  type        = string
  default     = ""
}

variable "allocate_eip" {
  description = "Allocate Elastic IP"
  type        = bool
  default     = true
}

# Optional - SSL
variable "ssl_method" {
  description = "SSL method: 'letsencrypt' or 'self-signed'"
  type        = string
  default     = "letsencrypt"
}

variable "ssl_email" {
  description = "Email for Let's Encrypt notifications"
  type        = string
  default     = ""
}

# Optional - Tags
variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
