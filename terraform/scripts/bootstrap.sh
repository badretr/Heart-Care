#!/bin/bash

# Heart Care Terraform Bootstrap Script
# This script creates the S3 backend and DynamoDB lock table

set -e

echo "=================================="
echo "Heart Care Terraform Bootstrap"
echo "=================================="

AWS_REGION=${1:-eu-west-1}
PROJECT_NAME="heartcare"

echo "AWS Region: $AWS_REGION"
echo "Project Name: $PROJECT_NAME"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install it."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Please run: aws configure"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install it."
    exit 1
fi

echo ""
echo "🔧 Initializing bootstrap..."

cd "$(dirname "$0")/../bootstrap"

# Create terraform.tfvars
cat > terraform.tfvars << EOF
aws_region = "$AWS_REGION"
project_name = "$PROJECT_NAME"
enable_lock_table = true
EOF

echo "✅ terraform.tfvars created"

# Initialize Terraform
echo ""
echo "🔄 Running terraform init..."
terraform init

# Apply bootstrap configuration
echo ""
echo "📝 Running terraform apply..."
terraform apply -auto-approve

# Get outputs
echo ""
echo "✅ Bootstrap complete!"
echo ""
echo "🔑 Terraform Backend Configuration:"
echo "======================================"
terraform output -raw backend_config_dev
echo ""
terraform output -raw backend_config_test
echo ""
terraform output -raw backend_config_prod
echo ""

# Generate init commands
echo "📋 Init Commands:"
echo "======================================"
echo "Development:"
terraform output -raw init_command_dev
echo ""
echo "Test:"
echo "terraform init -backend-config=bucket=$(terraform output -raw bucket_name) -backend-config=key=test/terraform.tfstate -backend-config=region=$AWS_REGION -backend-config=encrypt=true -backend-config=dynamodb_table=$(terraform output -raw dynamodb_table_name)"
echo ""
echo "Production:"
echo "terraform init -backend-config=bucket=$(terraform output -raw bucket_name) -backend-config=key=prod/terraform.tfstate -backend-config=region=$AWS_REGION -backend-config=encrypt=true -backend-config=dynamodb_table=$(terraform output -raw dynamodb_table_name)"
echo ""

echo "📖 Next steps:"
echo "1. Copy the backend configuration above"
echo "2. Go to each environment directory (dev, test, prod)"
echo "3. Run the appropriate init command"
echo "4. Create terraform.tfvars from terraform.tfvars.example"
echo "5. Run: terraform plan"
echo "6. Review the plan"
echo "7. Run: terraform apply"
