terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.36"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "OpenSearch domain name"
  type        = string
  default     = "opensearch-vpc-domain"
}

variable "master_username" {
  description = "Master username for OpenSearch"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "Master password for OpenSearch"
  type        = string
  default     = "TempPassword123!"
  sensitive   = true
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access"
  type        = string
  default     = "opensearch-key"
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Get current IP for security group
data "http" "current_ip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  current_ip = "${chomp(data.http.current_ip.response_body)}/32"
}

# VPC Configuration
resource "aws_vpc" "opensearch_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "opensearch-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "opensearch_igw" {
  vpc_id = aws_vpc.opensearch_vpc.id

  tags = {
    Name = "opensearch-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.opensearch_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "opensearch-public-subnet"
  }
}

# Private Subnets for OpenSearch (requires 2 AZs)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.opensearch_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "opensearch-private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.opensearch_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "opensearch-private-subnet-2"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.opensearch_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.opensearch_igw.id
  }

  tags = {
    Name = "opensearch-public-rt"
  }
}

# Route Table Association for Public Subnet
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for OpenSearch Domain
resource "aws_security_group" "opensearch_sg" {
  name        = "opensearch-domain-sg"
  description = "Security group for OpenSearch domain"
  vpc_id      = aws_vpc.opensearch_vpc.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
    description     = "HTTPS from EC2 instance"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "opensearch-domain-sg"
  }
}

# Security Group for EC2 Instance (Nginx)
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-nginx-sg"
  description = "Security group for EC2 instance running Nginx"
  vpc_id      = aws_vpc.opensearch_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.current_ip]
    description = "SSH from current IP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.current_ip]
    description = "HTTPS from current IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-nginx-sg"
  }
}

# Note: AWS automatically creates the service-linked role when creating VPC-enabled OpenSearch domains
# No need to create it manually

# OpenSearch Domain with VPC configuration
resource "aws_opensearch_domain" "vpc_domain" {
  domain_name    = var.domain_name
  engine_version = "OpenSearch_2.7"

  cluster_config {
    instance_type            = "r5.large.search"
    instance_count           = 1
    dedicated_master_enabled = false
  }

  vpc_options {
    subnet_ids = [
      aws_subnet.private_subnet_1.id
    ]
    security_group_ids = [aws_security_group.opensearch_sg.id]
  }

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  node_to_node_encryption {
    enabled = true
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 20
    volume_type = "gp3"
  }

  advanced_security_options {
    enabled                        = true
    anonymous_auth_enabled         = false
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.master_username
      master_user_password = var.master_password
    }
  }

  # Add open access policy for VPC domain (security is handled by security groups and fine-grained access control)
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}/*"
      }
    ]
  })

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_logs.arn
    log_type                 = "INDEX_SLOW_LOGS"
    enabled                  = true
  }

  depends_on = [aws_cloudwatch_log_resource_policy.opensearch_log_policy]

  tags = {
    Name = "opensearch-vpc-domain"
  }
}

# CloudWatch Log Group for OpenSearch
resource "aws_cloudwatch_log_group" "opensearch_logs" {
  name              = "/aws/opensearch/domains/${var.domain_name}"
  retention_in_days = 7

  tags = {
    Name = "opensearch-logs"
  }
}

# CloudWatch Log Resource Policy for OpenSearch
resource "aws_cloudwatch_log_resource_policy" "opensearch_log_policy" {
  policy_name = "opensearch-log-policy"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "es.amazonaws.com"
        }
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = "${aws_cloudwatch_log_group.opensearch_logs.arn}:*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}"
          }
        }
      }
    ]
  })
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# User data script for EC2 instance
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    opensearch_endpoint = aws_opensearch_domain.vpc_domain.endpoint
  }))
}

# EC2 Instance
resource "aws_instance" "nginx_proxy" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name              = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id             = aws_subnet.public_subnet.id

  user_data = local.user_data

  tags = {
    Name = "opensearch-nginx-proxy"
  }
}

# Outputs
output "opensearch_domain_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.vpc_domain.endpoint
}

output "opensearch_dashboard_url" {
  description = "OpenSearch Dashboard URL through Nginx proxy"
  value       = "https://${aws_instance.nginx_proxy.public_ip}/_dashboards"
}

output "ec2_public_ip" {
  description = "EC2 instance public IP"
  value       = aws_instance.nginx_proxy.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to EC2 instance"
  value       = "ssh -i ${var.key_pair_name}.pem ec2-user@${aws_instance.nginx_proxy.public_ip}"
}

output "master_credentials" {
  description = "OpenSearch master credentials"
  value = {
    username = var.master_username
    password = var.master_password
  }
  sensitive = true
}
