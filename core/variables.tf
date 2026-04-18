# ─────────────────────────────────────────────────────────────────────────────
# Auth – toggle
# ─────────────────────────────────────────────────────────────────────────────
variable "auth_mode" {
  description = "Auth mechanism: 'gha' for GitHub Actions OIDC, 'local' for IAM Roles Anywhere."
  type        = string
  validation {
    condition     = contains(["gha", "local"], var.auth_mode)
    error_message = "auth_mode must be 'gha' or 'local'."
  }
}

variable "aws_region" {
  description = "Target AWS region."
  type        = string
  default     = "us-east-1"
}

# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions OIDC  (auth_mode = "gha")
# ─────────────────────────────────────────────────────────────────────────────
variable "gha_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC (krypton-hosting-gha-exec). Output by create-gha-role.sh."
  type        = string
  default     = ""
}

variable "web_identity_token_file" {
  description = "Path to the OIDC web identity token file. The GHA workflow writes the token here before terraform runs."
  type        = string
  default     = "/tmp/web-identity-token"
}

variable "aws_profile" {
  description = "AWS CLI named profile for local execution. runner.sh creates this profile with credential_process backed by aws_signing_helper."
  type        = string
  default     = "krypton-ta"
}

# ── Identity ──────────────────────────────────────────────────────────────────
variable "organisation" {
  description = "Organisation identifier (from org.yml)."
  type        = string
  default     = "krypton"
}

variable "program" {
  description = "Program / product name (e.g. carevo)."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | stage | prod)."
  type        = string
}

variable "created_date" {
  description = "Date when the resources were created."
  type        = string
  default     = null
}
