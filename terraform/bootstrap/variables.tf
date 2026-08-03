variable "aws_region" {
  description = "AWS region for bootstrap resources"
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

variable "project_name" {
  description = "Project name used in IAM resource names"
  type        = string
  default     = "rearc-data"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default = {
    Project   = "rearc-data-quest"
    ManagedBy = "terraform"
  }
}
