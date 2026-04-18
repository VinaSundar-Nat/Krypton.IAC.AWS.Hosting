terraform {
  required_version = ">= 1.14"

  # Backend is configured at init time via -backend-config flags.
  # GHA passes S3 config; local runs use -backend=false (local state).
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.9.1"
    }
  }

  provider_meta "aws" {
    user_agent = [
      "github.com/VinaSundar-Nat/Krypton.IAC.AWS.Hosting"
    ]
  }
}
