.PHONY: help init plan apply destroy validate fmt build logs-sync logs-process test-sync test-process

ENV ?= dev
VAR_FILE := environments/$(ENV).tfvars

help:
	@echo "Rearc Data Quest — Terraform Makefile"
	@echo ""
	@echo "Usage: make <target> [ENV=dev|prod]"
	@echo ""
	@echo "  build           Build Lambda deployment packages"
	@echo "  init            Initialize Terraform"
	@echo "  validate        Validate & format-check Terraform"
	@echo "  fmt             Auto-format Terraform files"
	@echo "  plan            Show execution plan for ENV"
	@echo "  apply           Apply plan for ENV"
	@echo "  destroy         Destroy all resources for ENV (requires confirm)"
	@echo "  test-sync       Invoke data-sync Lambda manually"
	@echo "  test-process    Invoke data-process Lambda manually"
	@echo "  logs-sync       Tail data-sync CloudWatch logs"
	@echo "  logs-process    Tail data-process CloudWatch logs"
	@echo ""
	@echo "Examples:"
	@echo "  make apply ENV=dev"
	@echo "  make apply ENV=prod"
	@echo "  make destroy ENV=dev"

build:
	cd .. && bash scripts/build.sh

init:
	terraform init

validate:
	terraform validate
	terraform fmt -check -recursive

fmt:
	terraform fmt -recursive

plan:
	terraform plan -var-file=$(VAR_FILE) -out=tfplan-$(ENV)

apply:
	terraform apply tfplan-$(ENV)

destroy:
	@read -p "⚠️  Destroy ALL $(ENV) resources? Type 'yes' to confirm: " confirm; \
	[ "$$confirm" = "yes" ] && terraform destroy -var-file=$(VAR_FILE) -auto-approve || echo "Aborted."

test-sync:
	@FUNCTION=$$(terraform output -raw data_sync_function_name); \
	aws --region ap-south-1 lambda invoke \
	  --function-name $$FUNCTION \
	  --cli-binary-format raw-in-base64-out \
	  --payload '{"action":"sync_all"}' /tmp/response.json && \
	cat /tmp/response.json | python3 -m json.tool && rm -f /tmp/response.json

test-process:
	@FUNCTION=$$(terraform output -raw data_process_function_name); \
	BUCKET=$$(terraform output -raw s3_bucket_name); \
	aws --region ap-south-1 lambda invoke \
	  --function-name $$FUNCTION \
	  --cli-binary-format raw-in-base64-out \
	  --payload "{\"Records\":[{\"messageId\":\"test\",\"body\":\"{\\\"Records\\\":[{\\\"s3\\\":{\\\"bucket\\\":{\\\"name\\\":\\\"$$BUCKET\\\"},\\\"object\\\":{\\\"key\\\":\\\"population/data.json\\\"}}}]}\"}]}" \
	  /tmp/response.json && \
	cat /tmp/response.json | python3 -m json.tool && rm -f /tmp/response.json

logs-sync:
	@LOGS=$$(terraform output -raw cloudwatch_logs_data_sync); \
	aws --region ap-south-1 logs tail $$LOGS --follow

logs-process:
	@LOGS=$$(terraform output -raw cloudwatch_logs_data_process); \
	aws --region ap-south-1 logs tail $$LOGS --follow

s3-list:
	@BUCKET=$$(terraform output -raw s3_bucket_name); \
	aws --region ap-south-1 s3 ls s3://$$BUCKET/ --recursive

output:
	terraform output -var-file=$(VAR_FILE)

state-list:
	terraform state list

clean:
	rm -rf .terraform/ terraform.tfstate* tfplan-* .terraform.lock.hcl
