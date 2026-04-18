terraform {
  required_version = ">= 1.14"

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
