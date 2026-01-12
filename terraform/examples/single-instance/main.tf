# Single Instance Auth Gateway Example
# Cost-optimized deployment for small teams

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = var.name_prefix != "" ? var.name_prefix : "auth-gateway"
  az_list     = slice(data.aws_availability_zones.available.names, 0, min(2, length(data.aws_availability_zones.available.names)))

  common_tags = merge(
    var.tags,
    {
      Project     = "Auth Gateway"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  name_prefix               = local.name_prefix
  create_vpc                = var.create_vpc
  existing_vpc_id           = var.existing_vpc_id
  vpc_cidr                  = var.vpc_cidr
  availability_zones        = local.az_list
  allowed_cidr_blocks       = var.allowed_cidr_blocks
  ssh_allowed_cidr_blocks   = var.ssh_allowed_cidr_blocks

  tags = local.common_tags
}

# Compute Module
module "compute" {
  source = "../../modules/compute"

  name_prefix            = local.name_prefix
  region                 = var.region
  domain_name            = var.domain_name
  cognito_pool_id        = var.cognito_pool_id
  cognito_client_id      = var.cognito_client_id
  cognito_client_secret  = var.cognito_client_secret
  subnet_id              = module.networking.public_subnet_ids[0]
  security_group_id      = module.networking.security_group_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  allocate_eip           = var.allocate_eip
  ssl_method             = var.ssl_method
  ssl_email              = var.ssl_email

  tags = local.common_tags
}
