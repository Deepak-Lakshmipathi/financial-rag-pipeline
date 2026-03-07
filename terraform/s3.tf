data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "financial_docs" {
  bucket = "prog1-finrag-financial-docs"
  tags   = { Name = "financial-docs" }
}

resource "aws_s3_bucket_versioning" "financial_docs" {
  bucket = aws_s3_bucket.financial_docs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "financial_docs" {
  bucket = aws_s3_bucket.financial_docs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "financial_docs" {
  bucket                  = aws_s3_bucket.financial_docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "https_only" {
  bucket = aws_s3_bucket.financial_docs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonHTTPS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.financial_docs.arn,
        "${aws_s3_bucket.financial_docs.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}