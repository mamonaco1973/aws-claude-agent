# ===============================================================================
# REPORT BUCKET
# ===============================================================================
# The agent's only output channel. Private, versioned (so a bad night can't
# overwrite a good report for good) and encrypted with SSE-S3, which needs
# no KMS permissions on the task role.
# ===============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "reports" {
  bucket = "claude-agent-reports-${random_id.bucket_suffix.hex}"

  # destroy.sh empties the bucket first; this is the safety net.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
