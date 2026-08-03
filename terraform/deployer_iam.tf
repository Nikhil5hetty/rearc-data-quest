data "aws_partition" "current" {}

locals {
  deployer_bucket_name    = var.s3_bucket_name != "" ? var.s3_bucket_name : "rearc-raw-data-${var.environment}"
  deployer_sync_role_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/rearc-data-sync-role-*"
  deployer_proc_role_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/rearc-data-process-role-*"
  deployer_lambda_pattern = "arn:${data.aws_partition.current.partition}:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:rearc-data-*"
  deployer_queue_pattern  = "arn:${data.aws_partition.current.partition}:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rearc-data-process-queue-*"
  deployer_rule_pattern   = "arn:${data.aws_partition.current.partition}:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/rearc-data-sync-schedule-*"
}

data "aws_iam_policy_document" "deployer" {
  statement {
    sid    = "TerraformCallerIdentity"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformS3CreateAndList"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListAllMyBuckets"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformS3BucketConfiguration"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketEncryption",
      "s3:GetBucketLocation",
      "s3:GetBucketLogging",
      "s3:GetBucketNotification",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketReplication",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetBucketWebsite",
      "s3:ListBucket",
      "s3:PutBucketEncryption",
      "s3:PutBucketNotification",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:DeleteBucketPolicy"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.deployer_bucket_name}"]
  }

  statement {
    sid    = "TerraformS3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.deployer_bucket_name}/*"]
  }

  statement {
    sid    = "TerraformIamRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy"
    ]
    resources = [local.deployer_sync_role_arn, local.deployer_proc_role_arn]
  }

  statement {
    sid    = "TerraformIamAttachBasicExecutionManagedPolicy"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy"
    ]
    resources = [local.deployer_sync_role_arn, local.deployer_proc_role_arn]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
    }
  }

  statement {
    sid    = "TerraformPassProjectLambdaRolesToLambda"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [local.deployer_sync_role_arn, local.deployer_proc_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "TerraformLambdaCreateAndEventSourceMappingRead"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:CreateEventSourceMapping",
      "lambda:ListEventSourceMappings"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformLambdaManageProjectFunctions"
    effect = "Allow"
    actions = [
      "lambda:AddPermission",
      "lambda:DeleteFunction",
      "lambda:DeleteEventSourceMapping",
      "lambda:GetEventSourceMapping",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetPolicy",
      "lambda:ListTags",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:UpdateEventSourceMapping",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration"
    ]
    resources = [local.deployer_lambda_pattern]
  }

  statement {
    sid    = "TerraformSqsCreateListAndRead"
    effect = "Allow"
    actions = [
      "sqs:CreateQueue",
      "sqs:ListQueues",
      "sqs:GetQueueUrl"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformSqsManageProjectQueue"
    effect = "Allow"
    actions = [
      "sqs:AddPermission",
      "sqs:DeleteQueue",
      "sqs:GetQueueAttributes",
      "sqs:RemovePermission",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:UntagQueue"
    ]
    resources = [local.deployer_queue_pattern]
  }

  statement {
    sid    = "TerraformEventBridgeManageProjectRules"
    effect = "Allow"
    actions = [
      "events:DeleteRule",
      "events:DescribeRule",
      "events:DisableRule",
      "events:EnableRule",
      "events:ListTagsForResource",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource"
    ]
    resources = [local.deployer_rule_pattern]
  }

  statement {
    sid    = "TerraformEventBridgeReadTargets"
    effect = "Allow"
    actions = [
      "events:ListTargetsByRule"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_user" "deployer" {
  name = "rearc-data-deployer-${var.environment}"
  path = "/service/"

  tags = {
    Name    = "rearc-data-deployer-${var.environment}"
    Purpose = "Terraform deployer for rearc-data-quest (${var.environment})"
  }
}

resource "aws_iam_access_key" "deployer" {
  user = aws_iam_user.deployer.name
}

resource "aws_iam_policy" "deployer_policy" {
  name   = "rearc-data-deployer-policy-${var.environment}"
  path   = "/service/"
  policy = data.aws_iam_policy_document.deployer.json
}

resource "aws_iam_user_policy_attachment" "deployer_policy_attachment" {
  user       = aws_iam_user.deployer.name
  policy_arn = aws_iam_policy.deployer_policy.arn
}

output "deployer_iam_user_name" {
  description = "IAM user name for Terraform deployments"
  value       = aws_iam_user.deployer.name
}

output "deployer_access_key_id" {
  description = "Access key ID for deployer — add to AWS_ACCESS_KEY_ID"
  value       = aws_iam_access_key.deployer.id
  sensitive   = true
}

output "deployer_secret_access_key" {
  description = "Secret key for deployer — add to AWS_SECRET_ACCESS_KEY; store securely"
  value       = aws_iam_access_key.deployer.secret
  sensitive   = true
}
