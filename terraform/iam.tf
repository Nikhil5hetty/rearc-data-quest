# IAM Role for data-sync Lambda
resource "aws_iam_role" "data_sync_role" {
  name = "rearc-data-sync-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "data_sync_basic_execution" {
  role       = aws_iam_role.data_sync_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "data_sync_s3" {
  name = "rearc-data-sync-s3-${var.environment}"
  role = aws_iam_role.data_sync_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.data_bucket.arn, "${aws_s3_bucket.data_bucket.arn}/*"]
    }]
  })
}

# IAM Role for data-process Lambda
resource "aws_iam_role" "data_process_role" {
  name = "rearc-data-process-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "data_process_basic_execution" {
  role       = aws_iam_role.data_process_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "data_process_s3" {
  name = "rearc-data-process-s3-${var.environment}"
  role = aws_iam_role.data_process_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.data_bucket.arn, "${aws_s3_bucket.data_bucket.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy" "data_process_sqs" {
  name = "rearc-data-process-sqs-${var.environment}"
  role = aws_iam_role.data_process_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = aws_sqs_queue.data_process_queue.arn
    }]
  })
}

output "data_sync_role_arn" {
  value = aws_iam_role.data_sync_role.arn
}

output "data_process_role_arn" {
  value = aws_iam_role.data_process_role.arn
}
