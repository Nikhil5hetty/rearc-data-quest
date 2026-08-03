#!/usr/bin/env bash
# destroy.sh — Tear down all Rearc Data Quest cloud resources for a given environment.
# Usage:  bash scripts/destroy.sh [dev|prod]
#
# Requires: terraform, aws CLI, credentials configured for the deployer user.

set -euo pipefail

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
VAR_FILE="environments/${ENV}.tfvars"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   rearc-data-quest  —  DESTROY  (${ENV})              "
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "This will permanently destroy all AWS resources for environment: ${ENV}"
echo "  • S3 bucket: rearc-raw-data-${ENV}"
echo "  • Lambda:    rearc-data-sync-${ENV}"
echo "  • Lambda:    rearc-data-process-${ENV}"
echo "  • SQS queue: rearc-data-process-queue-${ENV}"
echo "  • IAM roles, EventBridge rules, S3 notifications"
echo ""
read -p "Type 'destroy-${ENV}' to confirm, or anything else to abort: " CONFIRM

if [ "$CONFIRM" != "destroy-${ENV}" ]; then
  echo "Aborted — no changes made."
  exit 0
fi

cd "$TF_DIR"

echo ""
echo "→ Initializing Terraform..."
terraform init -reconfigure

echo ""
echo "→ Planning destroy for ${ENV}..."
terraform plan -destroy -var-file="$VAR_FILE"

echo ""
read -p "Proceed with destroy? (yes/no): " FINAL
if [ "$FINAL" != "yes" ]; then
  echo "Aborted — no changes made."
  exit 0
fi

echo ""
echo "→ Destroying ${ENV} resources..."
terraform destroy -var-file="$VAR_FILE" -auto-approve

echo ""
echo "✓ Destroy complete for environment: ${ENV}"
