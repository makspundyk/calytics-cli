# =============================================================================
# Calytics Local Environment — Terraform Root Module
#
# Deploys AWS resources to LocalStack using the same patterns as real AWS.
# Usage:
#   cd terraform/local
#   terraform init
#   terraform apply -var-file=env/development.tfvars
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}
