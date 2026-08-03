variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "The environment must be either 'dev' or 'prod'."
  }
}

variable "s3_bucket_name" {
  description = "Override S3 bucket name. Leave blank to auto-generate as rearc-raw-data-{env}"
  type        = string
  default     = ""
}

variable "bls_prefix" {
  description = "S3 prefix for BLS data"
  type        = string
  default     = "bls/pr/"
}

variable "population_file_key" {
  description = "S3 key for the DataUSA population JSON"
  type        = string
  default     = "population/data.json"
}

variable "analytics_output_prefix" {
  description = "S3 prefix for analytics results"
  type        = string
  default     = "analytics/results/"
}

variable "data_sync_schedule" {
  description = "EventBridge cron schedule for the data-sync Lambda (UTC)"
  type        = string
  default     = "0 0 * * ? *"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default = {
    Project   = "rearc-data-quest"
    ManagedBy = "terraform"
  }
}
