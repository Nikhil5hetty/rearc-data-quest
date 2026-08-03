resource "aws_lambda_function" "data_process" {
  filename         = "${path.module}/../dist/data-process.zip"
  function_name    = local.data_process_fn
  role             = aws_iam_role.data_process_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = try(filebase64sha256("${path.module}/../dist/data-process.zip"), null)
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = 1024
  ephemeral_storage {
    size = 512
  }

  environment {
    variables = {
      S3_BUCKET           = aws_s3_bucket.data_bucket.id
      BLS_PREFIX          = var.bls_prefix
      POPULATION_FILE_KEY = var.population_file_key
      ENVIRONMENT         = var.environment
    }
  }

  tags = { Name = local.data_process_fn }

  depends_on = [
    aws_iam_role_policy.data_process_s3,
    aws_iam_role_policy.data_process_sqs,
    aws_iam_role_policy_attachment.data_process_basic_execution,
  ]
}

resource "aws_lambda_event_source_mapping" "sqs_to_data_process" {
  event_source_arn = aws_sqs_queue.data_process_queue.arn
  function_name    = aws_lambda_function.data_process.function_name
  batch_size       = 1
  enabled          = true

  depends_on = [
    aws_iam_role_policy.data_process_sqs,
    aws_lambda_permission.allow_sqs_data_process,
  ]
}

resource "aws_lambda_permission" "allow_sqs_data_process" {
  statement_id  = "AllowSQSDataProcess"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_process.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.data_process_queue.arn
}

output "data_process_function_name" {
  value = aws_lambda_function.data_process.function_name
}

output "data_process_function_arn" {
  value = aws_lambda_function.data_process.arn
}
