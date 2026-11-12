#!/bin/bash

# Heart Care Terraform Deploy Script
# Usage: ./deploy.sh [environment] [action]
# Example: ./deploy.sh dev plan
# Example: ./deploy.sh dev apply

set -e

ENVIRONMENT=${1:-dev}
ACTION=${2:-plan}

VALID_ENVIRONMENTS=("dev" "test" "prod")
VALID_ACTIONS=("plan" "apply" "destroy")

# Validate inputs
if [[ ! " ${VALID_ENVIRONMENTS[@]} " =~ " ${ENVIRONMENT} " ]]; then
    echo "❌ Invalid environment: $ENVIRONMENT"
    echo "Valid options: ${VALID_ENVIRONMENTS[@]}"
    exit 1
fi

if [[ ! " ${VALID_ACTIONS[@]} " =~ " ${ACTION} " ]]; then
    echo "❌ Invalid action: $ACTION"
    echo "Valid options: ${VALID_ACTIONS[@]}"
    exit 1
fi

# Production safety checks
if [[ "$ENVIRONMENT" == "prod" && "$ACTION" == "apply" ]]; then
    echo "⚠️  WARNING: You are about to apply changes to PRODUCTION!"
    echo "This will create/modify/delete REAL AWS resources."
    echo ""
    read -p "Type 'yes' to confirm: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "❌ Cancelled"
        exit 1
    fi
    echo ""
fi

# Change to environment directory
ENV_DIR="$(dirname "$0")/../environments/$ENVIRONMENT"
if [[ ! -d "$ENV_DIR" ]]; then
    echo "❌ Environment directory not found: $ENV_DIR"
    exit 1
fi

cd "$ENV_DIR"

echo "=================================="
echo "Heart Care Terraform - $ENVIRONMENT"
echo "Action: $ACTION"
echo "=================================="
echo ""

# Check if terraform.tfvars exists
if [[ ! -f "terraform.tfvars" ]]; then
    echo "❌ terraform.tfvars not found in $PWD"
    echo "Please create it from terraform.tfvars.example:"
    echo "  cp terraform.tfvars.example terraform.tfvars"
    exit 1
fi

# Check required variables in tfvars
REQUIRED_VARS=("db_password")
for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^$var" terraform.tfvars; then
        echo "❌ Missing required variable in terraform.tfvars: $var"
        exit 1
    fi
done

# Initialize Terraform if not already done
if [[ ! -d ".terraform" ]]; then
    echo "🔄 Initializing Terraform..."
    terraform init
    echo ""
fi

# Validate configuration
echo "✓ Validating Terraform configuration..."
terraform validate
echo ""

# Format check
echo "✓ Checking Terraform format..."
if ! terraform fmt -check -recursive > /dev/null 2>&1; then
    echo "⚠️  Format issues detected. Fixing..."
    terraform fmt -recursive
    echo "✅ Fixed"
fi
echo ""

case "$ACTION" in
    plan)
        echo "📋 Running terraform plan..."
        terraform plan -out=tfplan

        echo ""
        echo "📖 Review the plan above"
        echo "If it looks good, run:"
        echo "  ./deploy.sh $ENVIRONMENT apply"
        ;;

    apply)
        if [[ ! -f "tfplan" ]]; then
            echo "⚠️  No plan file found. Running plan first..."
            terraform plan -out=tfplan
            echo ""
        fi

        echo "📝 Applying Terraform configuration..."
        terraform apply tfplan

        echo ""
        echo "✅ Deployment complete!"
        echo ""
        echo "📊 Outputs:"
        terraform output
        ;;

    destroy)
        echo "⚠️  WARNING: This will destroy all infrastructure!"
        read -p "Type 'destroy' to confirm: " CONFIRM
        if [[ "$CONFIRM" != "destroy" ]]; then
            echo "❌ Cancelled"
            exit 1
        fi

        echo ""
        echo "🗑️  Running terraform destroy..."
        terraform destroy

        echo "✅ Destruction complete"
        ;;
esac

echo ""
echo "✨ Done!"
