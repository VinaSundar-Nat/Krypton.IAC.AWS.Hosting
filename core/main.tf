# =============================================================================
# main.tf
#
# AWS Provider auth is toggled by the `auth_mode` variable:
#
#   auth_mode = "gha"   → assume_role_with_web_identity
#                          GitHub Actions writes an OIDC token to
#                          `web_identity_token_file`; Terraform exchanges it
#                          for STS credentials directly using the GHA role.
#
#   auth_mode = "local" → Named AWS CLI profile (`aws_profile`) that uses
#                          credential_process = aws_signing_helper ...
#                          runner.sh writes this profile before terraform runs.
#                          aws_signing_helper exchanges the X.509 cert/key for
#                          temporary STS credentials via IAM Roles Anywhere.
#
# Switch modes by exporting TF_VAR_auth_mode=gha|local before terraform init.
# =============================================================================

locals {
  is_gha   = var.auth_mode == "gha"
  is_local = var.auth_mode == "local"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Program     = var.program
      Organization = var.organisation
      email       = "vinasundar.aws@gmail.com"
      ManagedBy   = "Terraform"
    }
  }

  # ── Local / IAM Roles Anywhere ─────────────────────────────────────────────
  # When auth_mode = "local", the named profile contains:
  #   credential_process = aws_signing_helper credential-process \
  #     --certificate   <cert.pem> \
  #     --private-key   <key.pem>  \
  #     --trust-anchor-arn <arn>   \
  #     --profile-arn      <arn>   \
  #     --role-arn         <arn>
  # runner.sh writes this profile before invoking terraform.
  profile = local.is_local ? var.aws_profile : null

  # ── GitHub Actions OIDC ────────────────────────────────────────────────────
  # When auth_mode = "gha", the GHA workflow must:
  #   1. Set `permissions: id-token: write` on the job.
  #   2. Write the OIDC token to web_identity_token_file:
  #        curl -sH "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  #          "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" \
  #          | jq -r .value > /tmp/web-identity-token
  #   3. Export TF_VAR_auth_mode=gha and TF_VAR_gha_role_arn=<arn>.
  dynamic "assume_role_with_web_identity" {
    for_each = local.is_gha ? [1] : []
    content {
      role_arn                = var.gha_role_arn
      web_identity_token_file = var.web_identity_token_file
      session_name            = "github-actions-terraform"
    }
  }
}

module "deploy-kr-vpc" {
  source   = "./module/network/vpc"
  cidr     = var.vpc_cidr
  enable_dns = var.vpc_enable_dns
  tags     = {
    Name = var.vpc_tags["name"]
  }
}
