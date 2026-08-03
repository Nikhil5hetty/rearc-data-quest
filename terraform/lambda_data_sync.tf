resource "aws_lambda_function" "data_sync" {
  filename         = "${path.module}/../dist/data-sync.zip"
  function_name    = local.data_sync_fn
  role             = aws_iam_role.data_sync_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = try(filebase64sha256("${path.module}/../dist/data-sync.zip"), null)
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      S3_BUCKET           = aws_s3_bucket.data_bucket.id
      BLS_PREFIX          = var.bls_prefix
      POPULATION_FILE_KEY = var.population_file_key
      ENVIRONMENT         = var.environment
    }
  }

  tags = { Name = local.data_sync_fn }

  depends_on = [
    aws_iam_role_policy.data_sync_s3,
    aws_iam_role_policy_attachment.data_sync_basic_execution,
  ]
}

resource "aws_cloudwatch_event_rule" "data_sync_schedule" {
  name                = "rearc-data-sync-schedule-${var.environment}"
  description         = "Daily trigger for data-sync Lambda (${var.environment})"
  schedule_expression = "cron(${var.data_sync_schedule})"
  tags                = { Name = "rearc-data-sync-schedule-${var.environment}" }
}

resource "aws_cloudwatch_event_target" "data_sync_lambda" {
  rule      = aws_cloudwatch_event_rule.data_sync_schedule.name
  target_id = "DataSyncLambda"
  arn       = aws_lambda_function.data_sync.arn
  input     = jsonencode({ action = "sync_all" })
}

resource "aws_lambda_permission" "allow_eventbridge_data_sync" {
  statement_id  = "AllowEventBridgeDataSync"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_sync.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_sync_schedule.arn
}

output "data_sync_function_name" {
  value = aws_lambda_function.data_sync.function_name
}

output "data_sync_function_arn" {
  value = aws_lambda_function.data_sync.arn
}

output "data_sync_schedule_name" {
  value = aws_cloudwatch_event_rule.data_sync_schedule.name
}
