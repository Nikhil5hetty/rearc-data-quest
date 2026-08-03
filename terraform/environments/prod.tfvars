aws_region  = "ap-south-1"
environment = "prod"

# Auto-generates as rearc-raw-data-prod; override to use a custom name
s3_bucket_name = ""

bls_prefix          = "bls/pr/"
population_file_key = "population/data.json"

# Daily at 01:00 UTC (offset from dev to spread load)
data_sync_schedule = "0 1 * * ? *"

lambda_timeout = 300
lambda_memory  = 1024

tags = {
  Project     = "rearc-data-quest"
  Environment = "prod"
  ManagedBy   = "terraform"
  Owner       = "data-team"
}
