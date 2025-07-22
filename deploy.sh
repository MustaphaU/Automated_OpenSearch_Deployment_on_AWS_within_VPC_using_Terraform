#!/bin/bash

# OpenSearch VPC Deployment Script
# This script helps deploy the OpenSearch VPC infrastructure using Terraform

set -e

echo " OpenSearch VPC Deployment Script"
echo "====================================="

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo " Terraform is not installed. Please install Terraform first."
    echo "Visit: https://terraform.io/downloads"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo " AWS CLI is not installed. Please install AWS CLI first."
    echo "Visit: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo " AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

echo "✅ Prerequisites check passed"

# Check if key pair exists
KEY_PAIR_NAME=${1:-"opensearch-key"}
REGION=${2:-"us-east-1"}

echo " Checking for EC2 key pair: $KEY_PAIR_NAME in region: $REGION"

if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$REGION" &> /dev/null; then
    echo "  Key pair '$KEY_PAIR_NAME' not found. Creating it..."
    
    # Create key pair and save private key
    aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --region "$REGION" --query 'KeyMaterial' --output text > "${KEY_PAIR_NAME}.pem"
    chmod 400 "${KEY_PAIR_NAME}.pem"
    
    echo "✅ Key pair created and saved as ${KEY_PAIR_NAME}.pem"
    echo "⚠️  IMPORTANT: Keep this file secure and backed up!"
else
    echo "✅ Key pair '$KEY_PAIR_NAME' already exists"
fi

# Check for OpenSearch master password
if [ -z "$OPENSEARCH_PASSWORD" ]; then
    echo "  OPENSEARCH_PASSWORD environment variable not set."
    echo "Please set it with: export OPENSEARCH_PASSWORD='YourSecurePassword123!'"
    echo "Password requirements:"
    echo "- At least 8 characters"
    echo "- At least one uppercase letter"
    echo "- At least one lowercase letter" 
    echo "- At least one number"
    echo "- At least one special character"
    exit 1
fi

echo "✅ OpenSearch password found in environment variable"

# Update terraform.tfvars if needed
if [ ! -f "terraform.tfvars" ]; then
    echo "📝 Creating terraform.tfvars file..."
    cat > terraform.tfvars << EOF
aws_region = "$REGION"
domain_name = "opensearch-vpc-domain"
master_username = "admin"
master_password = "$OPENSEARCH_PASSWORD"
key_pair_name = "$KEY_PAIR_NAME"
EOF
    echo " terraform.tfvars created with password from environment variable"
else
    # Update existing terraform.tfvars with new password
    echo " Updating terraform.tfvars with password from environment variable..."
    if command -v sed &> /dev/null; then
        sed -i "s/^master_password = .*/master_password = \"$OPENSEARCH_PASSWORD\"/" terraform.tfvars
    else
        # Fallback for systems without sed
        grep -v "^master_password = " terraform.tfvars > terraform.tfvars.tmp
        echo "master_password = \"$OPENSEARCH_PASSWORD\"" >> terraform.tfvars.tmp
        mv terraform.tfvars.tmp terraform.tfvars
    fi
    echo " terraform.tfvars updated with new password"
fi

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Validate configuration
echo "🔍 Validating Terraform configuration..."
terraform validate

# Plan deployment
echo " Planning deployment..."
terraform plan -out=tfplan

# Ask for confirmation
echo ""
echo " Ready to deploy? This will create AWS resources that may incur costs."
read -p "Do you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo " Deployment cancelled"
    exit 1
fi

# Apply configuration
echo " Deploying infrastructure..."
terraform apply tfplan

# Get outputs
echo ""
echo " Deployment completed successfully!"
echo ""
echo " Important Information:"
echo "========================"

DASHBOARD_URL=$(terraform output -raw opensearch_dashboard_url 2>/dev/null || echo "N/A")
EC2_IP=$(terraform output -raw ec2_public_ip 2>/dev/null || echo "N/A")
SSH_COMMAND=$(terraform output -raw ssh_command 2>/dev/null || echo "N/A")

echo " Dashboard URL: $DASHBOARD_URL"
echo "  EC2 Public IP: $EC2_IP"
echo " SSH Command: $SSH_COMMAND"
echo ""
echo " Next Steps:"
echo "1. Wait 5-10 minutes for the OpenSearch domain to become active"
echo "2. Access the dashboard using the URL above"
echo "3. Login with username 'admin' and the password you set in OPENSEARCH_PASSWORD"
echo "4. Accept the self-signed certificate warning in your browser"
echo ""
echo " Troubleshooting:"
echo "- SSH into EC2: $SSH_COMMAND"
echo "- Check Nginx logs: sudo tail -f /var/log/nginx/error.log"
echo "- Verify setup: sudo cat /var/log/opensearch-proxy-setup.log"
echo ""
echo "  Security Reminders:"
echo "- Use strong passwords and rotate them regularly"
echo "- Keep your private key (${KEY_PAIR_NAME}.pem) secure"
echo "- Monitor AWS costs and usage"
echo "- Consider using AWS Secrets Manager for production deployments"

# Clean up plan file
rm -f tfplan

echo ""
echo " Deployment script completed!"