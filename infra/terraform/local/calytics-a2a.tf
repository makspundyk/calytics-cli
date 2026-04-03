# =============================================================================
# calytics-a2a resources
#
# DynamoDB tables: NOT managed here — created by calytics-be-admin
# DynamoMigrationRunner on app bootstrap (Phase 3 of local-deploy.sh).
#
# A2A has no inline Terraform resources for DynamoDB/SQS/Secrets —
# everything is either in Lambda modules or app-managed.
#
# The mandate PDF S3 bucket is created here since it's Terraform-managed
# in the real environment.
# =============================================================================

resource "aws_s3_bucket" "mandate_pdf" {
  count  = var.enable_a2a ? 1 : 0
  bucket = "calytics-cc-${var.env}-pdf"
}
