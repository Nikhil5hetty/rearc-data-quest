locals {
  bucket_name     = var.s3_bucket_name != "" ? var.s3_bucket_name : "rearc-raw-data-${var.environment}"
  data_sync_fn    = "rearc-data-sync-${var.environment}"
  data_process_fn = "rearc-data-process-${var.environment}"
  queue_name      = "rearc-data-process-queue-${var.environment}"
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = local.bucket_name

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_versioning" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data_bucket" {
  bucket                  = aws_s3_bucket.data_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "data_bucket_notification" {
  bucket = aws_s3_bucket.data_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.data_process_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = var.population_file_key
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}
