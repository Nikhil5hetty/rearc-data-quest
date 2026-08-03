# Part 4: Infrastructure as Code & Data Pipeline with Terraform

This directory contains Terraform configuration for the Rearc Data Quest automated data pipeline.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     CloudWatch Events                           │
│           (Daily Schedule: 0:00 UTC)                            │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
        ┌────────────────────┐
        │  Lambda Part 1&2   │
        │  (BLS + DataUSA)   │
        └────────┬───────────┘
                 │
         ┌───────▼────────┐
         │                │
         ▼                ▼
    ┌────────┐      ┌─────────────────┐
    │  S3    │      │ SQS Queue       │
    │ Bucket │      │ (Event Trigger) │
    └────────┘      └────────┬────────┘
                             │
                             ▼
                    ┌────────────────────┐
                    │  Lambda Part 3     │
                    │  (Analytics)       │
                    │  - Query 1         │
                    │  - Query 2         │
                    │  - Query 3         │
                    └────────────────────┘
                             │
                             ▼
                      CloudWatch Logs
```

## Components

### 1. **S3 Bucket** (`s3.tf`)
- Centralized data storage for BLS data and population API results
- Versioning enabled for data history
- Server-side encryption for security
- Public access blocked
- S3 event notifications configured to trigger SQS

### 2. **SQS Queue** (`sqs.tf`)
- Triggered when population JSON file is written to S3
- Decouples Part 1&2 execution from Part 3 analytics
- 14-day message retention
- 15-minute visibility timeout

### 3. **Lambda Functions**

#### Data Sync (`lambda_data_sync.tf`)
- **Triggers**: CloudWatch Events (daily at 00:00 UTC)
- **Functions**:
  - Syncs BLS time-series data from official source
  - Fetches US population data from DataUSA API
  - Uploads results to S3 bucket
- **Runtime**: Python 3.11
- **Timeout**: 5 minutes
- **Memory**: 512 MB

#### Data Process (`lambda_data_process.tf`)
- **Triggers**: SQS messages (when population JSON is written)
- **Functions**:
  - Query 1: Population statistics (2013-2018)
  - Query 2: Best year per series (max annual sum)
  - Query 3: BLS-Population join (PRS30006032, Q01)
- **Runtime**: Python 3.11
- **Timeout**: 5 minutes
- **Memory**: 1024 MB
- **Ephemeral Storage**: 10 GB (for PySpark operations)

### 4. **IAM Roles & Policies** (`iam.tf`)
- Least-privilege access for Lambda functions
- S3 permissions for data access
- SQS permissions for message consumption
- CloudWatch Logs permissions for debugging

### 5. **CloudWatch Scheduling** (`lambda_data_sync.tf`)
- EventBridge rule for daily execution
- Configurable cron schedule (default: 0:00 UTC daily)
- All executions logged to CloudWatch

### 6. **Bootstrap Deployer User** (`bootstrap/`)
- Creates the Terraform deployer IAM user in a separate bootstrap-only root
- Keeps normal dev/prod Terraform applies free of IAM user creation
- Produces access keys as sensitive outputs during bootstrap only

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.0 installed
4. **Python** 3.11+ (for Lambda runtimes)

## Setup Instructions

### 1. Bootstrap the Terraform Deployer User (one-time)

Run once with an admin-capable IAM identity using the bootstrap root:

```bash
cd terraform/bootstrap
terraform init
terraform apply -var-file=../environments/dev.tfvars
```

Fetch and store credentials securely:

```bash
cd terraform/bootstrap
terraform output -raw deployer_access_key_id
terraform output -raw deployer_secret_access_key
```

The bootstrap root is separate from the main environment deploys, so normal CI runs will not recreate this IAM user.

### 2. Configure AWS Credentials

```bash
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1
```

Or configure via `~/.aws/credentials`:
```
[your-profile]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
```

### 2a. Configure GitHub Actions Secrets

For the CI workflows, create these secrets in each GitHub environment:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Use the `dev` environment secrets for [`.github/workflows/deploy-dev.yml`](/Users/Nikhil.Shetty@mheducation.com/Documents/UniB/rearc-data-quest/.github/workflows/deploy-dev.yml) and the `prod` environment secrets for [`.github/workflows/deploy-prod.yml`](/Users/Nikhil.Shetty@mheducation.com/Documents/UniB/rearc-data-quest/.github/workflows/deploy-prod.yml). The workflows now call `aws sts get-caller-identity` right after configuration so missing or invalid credentials fail fast with a clearer error.

### 3. Initialize Terraform

```bash
cd terraform
terraform init
```

### 4. Review Configuration

Edit `environments/dev.tfvars` or `environments/prod.tfvars` to customize:
- AWS region
- S3 bucket name (leave blank for auto-generated)
- Lambda schedule (cron format)
- Lambda timeout and memory allocation

```bash
cat environments/dev.tfvars
```

### 5. Build Lambda Packages

From the project root:

```bash
cd ..
bash scripts/build.sh
cd terraform
```

### 6. Plan Terraform Deployment

```bash
terraform plan -out=tfplan
```

Review the output to ensure all resources will be created as expected.

### 7. Apply Terraform Configuration

```bash
terraform apply tfplan
```

This will:
- Create or update the S3 bucket, SQS queue, Lambda functions, and EventBridge schedule
- Preserve the deployer user in `terraform/bootstrap/` only
- Let you target `plan`, `apply`, `destroy`, `bootstrap`, or selected resources from the GitHub Actions workflow

### 8. Verify Deployment

```bash
# Get deployment summary
terraform output deployment_summary

# Show S3 bucket name
terraform output s3_bucket_name

# Show CloudWatch Logs paths
terraform output cloudwatch_logs_data_sync
terraform output cloudwatch_logs_data_process
```

## Testing

### Test Part 1&2 Lambda

```bash
# Get function name
FUNCTION_NAME=$(terraform output -raw data_sync_function_name)

# Invoke manually
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{"action": "sync_all"}' \
  response.json

# View response
cat response.json | jq .
```

### Test Part 3 Lambda

```bash
# Get function name
FUNCTION_NAME=$(terraform output -raw data_process_function_name)

# Invoke manually with test event
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{"Records": [{"messageId": "test"}]}' \
  response.json

# View response
cat response.json | jq .
```

### View CloudWatch Logs

```bash
# Part 1&2 logs
aws logs tail /aws/lambda/rearc-data-sync-dev --follow

# Part 3 logs
aws logs tail /aws/lambda/rearc-data-process-dev --follow
```

## Monitoring

### CloudWatch Dashboards

View Lambda execution metrics:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=rearc-data-sync-dev \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### SQS Queue Status

```bash
QUEUE_URL=$(terraform output -raw sqs_queue_url)

aws sqs get-queue-attributes \
  --queue-url $QUEUE_URL \
  --attribute-names All
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will delete:
- S3 bucket (including all data)
- SQS queue
- Lambda functions
- IAM roles
- CloudWatch rules

Ensure you've backed up any important data before destroying.

## File Structure

```
terraform/
├── main.tf                 # Main provider configuration
├── variables.tf            # Variable definitions
├── environments/           # Dev/prod variable files
├── outputs.tf              # Output definitions
├── bootstrap/              # Bootstrap-only deployer user Terraform root
├── s3.tf                   # S3 bucket configuration
├── sqs.tf                  # SQS queue configuration
├── iam.tf                  # IAM roles and policies
├── lambda_data_sync.tf      # Data sync Lambda function
├── lambda_data_process.tf   # Data process Lambda function
└── README.md               # This file

../lambdas/
├── data-sync/
│   ├── bls_sync.py         # BLS sync implementation
│   ├── datausa_api.py      # DataUSA API implementation
│   └── handler.py          # Data sync Lambda handler
├── data-process/
│   └── handler.py          # Data process Lambda handler
└── requirements.txt        # Python dependencies
```

## Environment Variables

Lambda functions use the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `S3_BUCKET` | S3 bucket name | (set by Terraform) |
| `BLS_PREFIX` | S3 prefix for BLS data | `bls/pr/` |
| `POPULATION_FILE_KEY` | S3 key for population JSON | `population/data.json` |
| `ENVIRONMENT` | Environment name | `dev` |

## Troubleshooting

### Lambda Function Fails

1. Check CloudWatch Logs:
   ```bash
   aws logs tail /aws/lambda/rearc-data-sync-dev --follow
   ```

2. Verify IAM permissions:
   ```bash
   aws iam get-role-policy \
     --role-name rearc-data-sync-role-dev \
     --policy-name rearc-data-sync-s3-dev
   ```

3. Test S3 access:
   ```bash
   BUCKET=$(terraform output -raw s3_bucket_name)
   aws s3 ls s3://$BUCKET/
   ```

### SQS Queue Not Triggering Lambda

1. Verify S3 event notification:
   ```bash
   BUCKET=$(terraform output -raw s3_bucket_name)
   aws s3api get-bucket-notification-configuration --bucket $BUCKET
   ```

2. Check SQS permissions:
   ```bash
   aws sqs get-queue-attributes \
     --queue-url $(terraform output -raw sqs_queue_url) \
     --attribute-names Policy
   ```

### CloudWatch Events Not Triggering

1. Verify rule is enabled:
   ```bash
   aws events describe-rule --name rearc-data-sync-schedule-dev
   ```

2. Check rule targets:
   ```bash
   aws events list-targets-by-rule --rule rearc-data-sync-schedule-dev
   ```

## Advanced Configuration

### Using S3 Backend for State

Create `backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "rearc-data-quest/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### Custom Schedule

Edit `environments/dev.tfvars` or `environments/prod.tfvars`:
```hcl
lambda_part1_2_schedule = "0 */6 * * ? *"  # Every 6 hours
```

Cron format examples:
- `0 0 * * ? *` - Daily at midnight
- `0 */6 * * ? *` - Every 6 hours
- `0 9 * * MON-FRI ? *` - Weekdays at 9 AM

## Cost Estimation

Estimated monthly costs (rough):
- **S3**: $0.023 per GB (data storage) + requests
- **Lambda**: $0.20 per 1M requests + $0.0000166667/GB-second
- **SQS**: $0.40 per 1M requests
- **CloudWatch**: $0.50 per log group + log storage

For minimal usage (daily execution, few GB data), expect <$5/month.

## Next Steps

1. Configure AWS credentials
2. Run `terraform init`
3. Review `environments/dev.tfvars` or `environments/prod.tfvars`
4. Run `terraform plan`
5. Run `terraform apply`
6. Test Lambda functions manually
7. Monitor CloudWatch Logs
8. Set up alarms for failures (optional)

## Support & Documentation

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS SQS Documentation](https://docs.aws.amazon.com/sqs/)
- [AWS EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
