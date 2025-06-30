#!/bin/bash

# OpenSearch VPC Cleanup Script
# This script helps destroy the OpenSearch VPC infrastructure

set -e

echo "🧹 OpenSearch VPC Cleanup Script"
echo "================================="

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed."
    exit 1
fi

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo "⚠️  No Terraform state file found. Nothing to destroy."
    exit 0
fi

# Show what will be destroyed
echo "🔍 Planning destruction..."
terraform plan -destroy

echo ""
echo "⚠️  WARNING: This will destroy ALL resources created by this Terraform configuration!"
echo "This includes:"
echo "- OpenSearch domain and all data"
echo "- EC2 instance"
echo "- VPC and all networking components"
echo "- Security groups"
echo "- CloudWatch log groups"
echo ""
echo "💡 Make sure to backup any important data before proceeding."
echo ""

# Ask for confirmation
read -p "Are you absolutely sure you want to destroy all resources? (type 'yes' to confirm): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "❌ Destruction cancelled"
    exit 1
fi

# Destroy infrastructure
echo "🗑️  Destroying infrastructure..."
terraform destroy -auto-approve

echo ""
echo "🎉 All resources have been destroyed successfully!"
echo ""
echo "📋 Manual cleanup (if needed):"
echo "- EC2 key pair (if created by the deploy script)"
echo "- Any manual backups you may have created"
echo ""
echo "💡 The private key file (.pem) has been preserved in case you need it later."

echo ""
echo "🧹 Cleanup completed!"
