#!/bin/bash

# AWS Login and EKS Node Check Script

# Configuration
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate inputs
if [ -z "$EKS_CLUSTER_NAME" ]; then
  echo -e "${RED}Error: EKS_CLUSTER_NAME must be set${NC}"
  echo "Usage: EKS_CLUSTER_NAME=my-cluster AWS_REGION=us-east-1 $0"
  exit 1
fi

# Configure AWS CLI credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo -e "${RED}Error: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables must be set${NC}"
  exit 1
fi

echo -e "${YELLOW}Configuring AWS credentials...${NC}"
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_REGION

# Test AWS CLI connection
echo -e "${YELLOW}Testing AWS CLI connection...${NC}"
if ! aws sts get-caller-identity --region "$AWS_REGION" > /dev/null 2>&1; then
  echo -e "${RED}Failed to authenticate with AWS. Check your credentials.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ AWS authentication successful${NC}"

# Update kubeconfig for EKS cluster
echo -e "${YELLOW}Updating kubeconfig for cluster: $EKS_CLUSTER_NAME${NC}"
if ! aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"; then
  echo -e "${RED}Failed to update kubeconfig${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Kubeconfig updated${NC}"

# List EKS nodes (credentials must remain available)
echo -e "${YELLOW}Listing nodes in EKS cluster: $EKS_CLUSTER_NAME${NC}"
echo ""

# Ensure AWS credentials are available for kubectl authentication
if AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" AWS_REGION="$AWS_REGION" kubectl get nodes; then
  echo -e "${GREEN}✓ Successfully retrieved nodes${NC}"
else
  echo -e "${RED}Failed to retrieve nodes${NC}"
  exit 1
fi

# Optional: Show detailed node information
echo ""
echo -e "${YELLOW}Detailed node information:${NC}"
AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" AWS_REGION="$AWS_REGION" kubectl get nodes -o wide
