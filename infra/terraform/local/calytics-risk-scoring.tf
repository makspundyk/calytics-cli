# =============================================================================
# calytics-risk-scoring — Reuses the existing Terraform module directly
# Source: calytics-risk-scoring/terraform/modules/dynamodb/main.tf
#
# Creates: iban-reputation, current-scores, score-history, velocity tables
# =============================================================================

module "risk_scoring_dynamodb" {
  count  = var.enable_risk_scoring ? 1 : 0
  source = "../../../../calytics-risk-scoring/terraform/modules/dynamodb"
  env    = var.env
}
