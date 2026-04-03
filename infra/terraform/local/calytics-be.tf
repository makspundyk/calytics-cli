# =============================================================================
# calytics-be resources — S3, SQS, Secrets Manager, DynamoDB
# Mirrors: calytics-be/terraform/environments/development/main.tf
# =============================================================================

locals {
  be_service = "calytics-be"
  be_prefix  = "${local.be_service}-${var.env}"
}

# ── SSM Parameters ───────────────────────────────────────────────

resource "terraform_data" "ssm_account_id" {
  count = var.enable_be ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      aws --endpoint-url=${var.localstack_endpoint} ssm put-parameter \
        --name "/accountId" --value "${var.aws_account_id}" \
        --type String --region ${var.aws_region} --overwrite 2>/dev/null || true
    EOT
  }
}

# ── S3 Buckets ───────────────────────────────────────────────────

resource "aws_s3_bucket" "admin" {
  count  = var.enable_be ? 1 : 0
  bucket = "${local.be_prefix}-admin"
}

# ── SQS Queues ───────────────────────────────────────────────────

resource "aws_sqs_queue" "data_enrichment_dlq" {
  count                       = var.enable_be ? 1 : 0
  name                        = "${local.be_prefix}-data-enrichment-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
}

resource "aws_sqs_queue" "data_enrichment" {
  count                       = var.enable_be ? 1 : 0
  name                        = "${local.be_prefix}-data-enrichment.fifo"
  fifo_queue                  = true
  content_based_deduplication = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.data_enrichment_dlq[0].arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "client_callback_dlq" {
  count                     = var.enable_be ? 1 : 0
  name                      = "${local.be_prefix}-client-callback-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "client_callback" {
  count                      = var.enable_be ? 1 : 0
  name                       = "${local.be_prefix}-client-callback"
  visibility_timeout_seconds = 70
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.client_callback_dlq[0].arn
    maxReceiveCount     = 4
  })
}

resource "aws_sqs_queue" "dead_letter_fifo" {
  count                       = var.enable_be ? 1 : 0
  name                        = "${local.be_prefix}-dead-letter.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
}

resource "aws_sqs_queue" "jobs" {
  count                      = var.enable_be ? 1 : 0
  name                       = "${local.be_prefix}-jobs"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
}

# ── Secrets Manager ──────────────────────────────────────────────

resource "aws_secretsmanager_secret" "api_key_encryption" {
  count = var.enable_be ? 1 : 0
  name  = "calytics-be-admin/api-key-encryption"
}

resource "aws_secretsmanager_secret_version" "api_key_encryption" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.api_key_encryption[0].id
  secret_string = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}

resource "aws_secretsmanager_secret" "webhook_encryption" {
  count = var.enable_be ? 1 : 0
  name  = "calytics-be-admin/webhook-encryption"
}

resource "aws_secretsmanager_secret_version" "webhook_encryption" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.webhook_encryption[0].id
  secret_string = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
}

resource "aws_secretsmanager_secret" "ui_validator" {
  count = var.enable_be ? 1 : 0
  name  = "calytics/local/api-key/ui-validator"
}

resource "aws_secretsmanager_secret_version" "ui_validator" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.ui_validator[0].id
  secret_string = "local-ui-validator-api-key-secret"
}

# ── Vendor Credentials (stubs) ───────────────────────────────────

resource "aws_secretsmanager_secret" "finapi_credentials" {
  count = var.enable_be ? 1 : 0
  name  = "calytics/calytics-be/${var.env}/finapi/credentials"
}

resource "aws_secretsmanager_secret_version" "finapi_credentials" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.finapi_credentials[0].id
  secret_string = var.finapi_credentials
}

resource "aws_secretsmanager_secret" "finapi_static" {
  count = var.enable_be ? 1 : 0
  name  = "calytics/calytics-be/${var.env}/finapi/static-credentials"
}

resource "aws_secretsmanager_secret_version" "finapi_static" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.finapi_static[0].id
  secret_string = var.finapi_credentials
}

resource "aws_secretsmanager_secret" "qonto_credentials" {
  count = var.enable_be ? 1 : 0
  name  = "calytics/qonto/credentials"
}

resource "aws_secretsmanager_secret_version" "qonto_credentials" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.qonto_credentials[0].id
  secret_string = var.qonto_credentials
}

resource "aws_secretsmanager_secret" "qonto_static" {
  count = var.enable_be ? 1 : 0
  name  = "calytics/qonto/static-credentials"
}

resource "aws_secretsmanager_secret_version" "qonto_static" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.qonto_static[0].id
  secret_string = var.qonto_credentials
}

resource "aws_secretsmanager_secret" "revolut_credentials" {
  count = var.enable_be ? 1 : 0
  name  = "calytics/calytics-be/${var.env}/revolut/credentials"
}

resource "aws_secretsmanager_secret_version" "revolut_credentials" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.revolut_credentials[0].id
  secret_string = var.revolut_credentials
}

resource "aws_secretsmanager_secret" "revolut_static" {
  count = var.enable_be ? 1 : 0
  name  = "calytics/calytics-be/${var.env}/revolut/static-credentials"
}

resource "aws_secretsmanager_secret_version" "revolut_static" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.revolut_static[0].id
  secret_string = var.revolut_credentials
}

resource "aws_secretsmanager_secret" "brd_credentials" {
  count = var.enable_be ? 1 : 0
  name  = "calytics/local/bright-data/credentials"
}

resource "aws_secretsmanager_secret_version" "brd_credentials" {
  count         = var.enable_be ? 1 : 0
  secret_id     = aws_secretsmanager_secret.brd_credentials[0].id
  secret_string = "{\"username\":\"local\",\"password\":\"local\"}"
}

# ── DynamoDB Tables ──────────────────────────────────────────────
# NOT managed here — created by calytics-be-admin DynamoMigrationRunner
# on app bootstrap (Phase 3 of local-deploy.sh). Defining them here
# would conflict with the app's table creation.

