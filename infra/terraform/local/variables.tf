# =============================================================================
# Variables
# =============================================================================

variable "env" {
  description = "Environment name (maps to table/queue naming)"
  type        = string
  default     = "local"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}

variable "aws_account_id" {
  description = "AWS account ID (dummy for LocalStack)"
  type        = string
  default     = "000000000000"
}

# ── Feature flags ────────────────────────────────────────────────

variable "enable_be" {
  description = "Deploy calytics-be resources (S3, SQS, Secrets, DDB tables)"
  type        = bool
  default     = true
}

variable "enable_a2a" {
  description = "Deploy calytics-a2a resources"
  type        = bool
  default     = true
}

variable "enable_risk_scoring" {
  description = "Deploy risk-scoring DynamoDB tables"
  type        = bool
  default     = true
}

variable "enable_lambdas" {
  description = "Deploy Lambda functions to LocalStack (terraform-mode)"
  type        = bool
  default     = false
}

# ── Vendor credential stubs ─────────────────────────────────────

variable "finapi_credentials" {
  description = "FinAPI credentials JSON"
  type        = string
  default     = "{\"client_id\":\"local\",\"client_secret\":\"local\"}"
}

variable "revolut_credentials" {
  description = "Revolut credentials JSON"
  type        = string
  default     = "{\"client_id\":\"local\",\"client_secret\":\"local\"}"
}

variable "qonto_credentials" {
  description = "Qonto credentials JSON"
  type        = string
  default     = "{\"client_id\":\"local\",\"client_secret\":\"local\"}"
}

# ── Lambda package paths (only used when enable_lambdas = true) ──

variable "be_lambda_package_path" {
  description = "Path to calytics-be Lambda deployment packages"
  type        = string
  default     = "../../calytics-be/dist/terraform-lambdas"
}

variable "a2a_lambda_package_path" {
  description = "Path to calytics-a2a Lambda deployment packages"
  type        = string
  default     = "../../calytics-a2a/dist/terraform-lambdas"
}

variable "risk_scoring_lambda_package_path" {
  description = "Path to risk-scoring Lambda deployment packages"
  type        = string
  default     = "../../calytics-risk-scoring/dist/terraform-lambdas"
}
