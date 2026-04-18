# =============================================================================
# core/terraform.tfvars — MASTER TEMPLATE
#
# REPLACE_* tokens are substituted by scripts/replace-vars.sh at runtime.
# Restored to this state by scripts/revert-master-vars.sh after terraform runs.
#
# Source:
#   environment/org.yml  → organisation, program, environment tags
#
# DO NOT edit REPLACE_* tokens — edit environment/org.yml instead.
# DO NOT set auth_mode here — export TF_VAR_auth_mode=gha|local at the shell.
# =============================================================================

aws_region = "REPLACE_REGION"
# auth_mode is intentionally omitted — supply via TF_VAR_auth_mode env var
# or -var 'auth_mode=...' flag.  See runner.sh (local) and plan-deploy.yml (gha).

# ── GitHub Actions OIDC ───────────────────────────────────────────────────────
# Role created by .auth/create-gha-role.sh
gha_role_arn            = "arn:aws:iam::ACCOUNT_ID:role/krypton-hosting-gha-exec"
web_identity_token_file = "/tmp/web-identity-token"

# ── IAM Roles Anywhere (local/on-prem) ───────────────────────────────────────
# ARNs live in scripts/vars.sh — only the named profile is needed here.
aws_profile               = "krypton-ta"

organisation = "REPLACE_ORGANISATION"
program      = "REPLACE_PROGRAM"
environment  = "REPLACE_ENVIRONMENT"
