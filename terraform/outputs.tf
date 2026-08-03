output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment         = var.environment
    region              = data.aws_region.current.name
    account_id          = data.aws_caller_identity.current.account_id
    s3_bucket_name      = aws_s3_bucket.data_bucket.id
    s3_bucket_arn       = aws_s3_bucket.data_bucket.arn
    sqs_queue_url       = aws_sqs_queue.data_process_queue.id
    sqs_queue_arn       = aws_sqs_queue.data_process_queue.arn
    data_sync_name      = aws_lambda_function.data_sync.function_name
    data_sync_arn       = aws_lambda_function.data_sync.arn
    data_process_name   = aws_lambda_function.data_process.function_name
    data_process_arn    = aws_lambda_function.data_process.arn
    schedule_expression = aws_cloudwatch_event_rule.data_sync_schedule.schedule_expression
  }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.data_bucket.id
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.data_bucket.arn
}

output "cloudwatch_logs_data_sync" {
  value = "/aws/lambda/${aws_lambda_function.data_sync.function_name}"
}

output "cloudwatch_logs_data_process" {
  value = "/aws/lambda/${aws_lambda_function.data_process.function_name}"
}

output "data_sync_invoke_command" {
  value = "aws lambda invoke --function-name ${aws_lambda_function.data_sync.function_name} --payload '{\"action\":\"sync_all\"}' response.json"
}

output "data_process_invoke_command" {
  value = "aws lambda invoke --function-name ${aws_lambda_function.data_process.function_name} --payload '{\"test\":true}' response.json"
}
