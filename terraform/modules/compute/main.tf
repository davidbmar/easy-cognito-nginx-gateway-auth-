# Compute Module for Auth Gateway EC2 Instance

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "gateway" {
  name = "${var.name_prefix}-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for Gateway
resource "aws_iam_role_policy" "gateway" {
  name = "${var.name_prefix}-gateway-policy"
  role = aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secrets_manager_arns
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "gateway" {
  name = "${var.name_prefix}-gateway-profile"
  role = aws_iam_role.gateway.name

  tags = var.tags
}

# User Data Script
locals {
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    domain_name            = var.domain_name
    cognito_pool_id        = var.cognito_pool_id
    cognito_client_id      = var.cognito_client_id
    cognito_client_secret  = var.cognito_client_secret
    region                 = var.region
    ssl_method             = var.ssl_method
    ssl_email              = var.ssl_email
    install_script_url     = var.install_script_url
  })
}

# EC2 Instance
resource "aws_instance" "gateway" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.gateway.name
  key_name               = var.key_name

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2
    http_put_response_hop_limit = 1
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-gateway"
    }
  )
}

# Elastic IP (optional)
resource "aws_eip" "gateway" {
  count = var.allocate_eip ? 1 : 0

  instance = aws_instance.gateway.id
  domain   = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-gateway-eip"
    }
  )
}
