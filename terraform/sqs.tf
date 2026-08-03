resource "aws_sqs_queue" "data_process_queue" {
  name                       = local.queue_name
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 900     # 15 minutes

  tags = {
    Name = local.queue_name
  }
}

resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.data_process_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.data_process_queue.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_s3_bucket.data_bucket.arn }
      }
    }]
  })
}

output "sqs_queue_url" {
  value = aws_sqs_queue.data_process_queue.id
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.data_process_queue.arn
}
