#!/usr/bin/env bash
set -euo pipefail

# AWS Login and EKS Node Check Script

# Configuration
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
EKS_ASSUME_ROLE_ARN="${EKS_ASSUME_ROLE_ARN:-arn:aws:iam::210620017481:role/kr-carevo-dev-cluster-adm-role}"

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

if ! command -v aws >/dev/null 2>&1; then
  echo -e "${RED}Error: aws CLI is not installed${NC}"
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo -e "${RED}Error: kubectl is not installed${NC}"
  exit 1
fi

# Determine credential source:
# 1) Explicit env credentials (access key + secret, optional session token)
# 2) AWS profile
if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo -e "${YELLOW}Using environment AWS credentials...${NC}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
  if [ -n "${AWS_SESSION_TOKEN:-}" ]; then
    export AWS_SESSION_TOKEN
  fi
  unset AWS_PROFILE
else
  echo -e "${YELLOW}Using AWS profile: ${AWS_PROFILE}${NC}"
  export AWS_PROFILE AWS_REGION
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
fi

# Assume role for EKS access and export temporary credentials.
echo -e "${YELLOW}Assuming role: ${EKS_ASSUME_ROLE_ARN}${NC}"
ROLE_CREDS="$(aws sts assume-role \
  --role-arn "$EKS_ASSUME_ROLE_ARN" \
  --role-session-name "eks-cluster-test-$(date +%s)" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]' \
  --output text \
  --region "$AWS_REGION")"

if [ -z "$ROLE_CREDS" ]; then
  echo -e "${RED}Failed to assume role${NC}"
  exit 1
fi

export AWS_ACCESS_KEY_ID="$(echo "$ROLE_CREDS" | awk '{print $1}')"
export AWS_SECRET_ACCESS_KEY="$(echo "$ROLE_CREDS" | awk '{print $2}')"
export AWS_SESSION_TOKEN="$(echo "$ROLE_CREDS" | awk '{print $3}')"
ROLE_EXPIRATION="$(echo "$ROLE_CREDS" | awk '{print $4}')"
unset AWS_PROFILE

echo -e "${GREEN}✓ Temporary role credentials exported (expires: ${ROLE_EXPIRATION})${NC}"

# Test AWS identity
echo -e "${YELLOW}Testing AWS identity...${NC}"
if ! aws sts get-caller-identity --region "$AWS_REGION"; then
  echo -e "${RED}Failed to authenticate with AWS. Check credentials/profile/role.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ AWS authentication successful${NC}"

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig for cluster: $EKS_CLUSTER_NAME${NC}"
if ! aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --role-arn "$EKS_ASSUME_ROLE_ARN"; then
  echo -e "${RED}Failed to update kubeconfig${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Kubeconfig updated${NC}"

# Validate EKS token generation (this is what kubectl exec auth relies on)
echo -e "${YELLOW}Validating EKS token generation...${NC}"
if ! aws eks get-token --cluster-name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null; then
  echo -e "${RED}Failed to generate EKS token. Credentials likely missing/expired/unauthorized.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ EKS token generation successful${NC}"

kubectl get svc >/dev/null 2>&1 || {
  echo -e "${RED}Failed to connect to EKS cluster. Check network, cluster status, and IAM permissions.${NC}"
  exit 1
}
echo -e "${GREEN}✓ Connected to EKS cluster${NC}"

# List nodes
echo -e "${YELLOW}Listing nodes in EKS cluster: $EKS_CLUSTER_NAME${NC}"
if kubectl get nodes; then
  echo -e "${GREEN}✓ Successfully retrieved nodes${NC}"
else
  echo -e "${RED}Failed to retrieve nodes${NC}"
  echo -e "${YELLOW}Hint: ensure this IAM principal has EKS access entry/policy on the cluster.${NC}"
  exit 1
fi

# Optional detailed output
echo ""
echo -e "${YELLOW}Detailed node information:${NC}"
kubectl get nodes -o wide