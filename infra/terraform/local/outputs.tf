# =============================================================================
# Outputs — Queue URLs, bucket names
# DynamoDB tables are app-managed (not Terraform) so no outputs for those.
# =============================================================================

# ── SQS ──────────────────────────────────────────────────────────

output "data_enrichment_queue_url" {
  value = var.enable_be ? aws_sqs_queue.data_enrichment[0].url : ""
}

output "client_callback_queue_url" {
  value = var.enable_be ? aws_sqs_queue.client_callback[0].url : ""
}

output "dead_letter_fifo_queue_url" {
  value = var.enable_be ? aws_sqs_queue.dead_letter_fifo[0].url : ""
}

# ── S3 ───────────────────────────────────────────────────────────

output "admin_bucket" {
  value = var.enable_be ? aws_s3_bucket.admin[0].id : ""
}

output "mandate_pdf_bucket" {
  value = var.enable_a2a ? aws_s3_bucket.mandate_pdf[0].id : ""
}

# ── Risk Scoring Tables (module-managed) ─────────────────────────

output "risk_scoring_tables" {
  value = var.enable_risk_scoring ? {
    iban_reputation = module.risk_scoring_dynamodb[0].iban_reputation_table_name
    current_scores  = module.risk_scoring_dynamodb[0].current_scores_table_name
    score_history   = module.risk_scoring_dynamodb[0].score_history_table_name
    velocity        = module.risk_scoring_dynamodb[0].velocity_table_name
  } : {}
}
