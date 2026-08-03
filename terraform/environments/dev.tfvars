aws_region  = "ap-south-1"
environment = "dev"

# Auto-generates as rearc-raw-data-dev; override to use a custom name
s3_bucket_name = ""

bls_prefix          = "bls/pr/"
population_file_key = "population/data.json"

# Daily at midnight UTC
data_sync_schedule = "0 0 * * ? *"

lambda_timeout = 300
lambda_memory  = 512

tags = {
  Project     = "rearc-data-quest"
  Environment = "dev"
  ManagedBy   = "terraform"
  Owner       = "data-team"
}
