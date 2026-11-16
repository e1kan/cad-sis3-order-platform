#!/usr/bin/env bash
# ./destroy.sh [app-stack] [network-stack]   - app stack first (the network exports are imported by it)
set -euo pipefail
APP_STACK="${1:-cad-sis3-app}"; NET_STACK="${2:-cad-sis3-network}"; REGION="${AWS_REGION:-eu-central-1}"
TABLE="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$APP_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='TableName'].OutputValue" --output text)"
aws cloudformation delete-stack --region "$REGION" --stack-name "$APP_STACK"
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$APP_STACK"
[ "${KEEP_NETWORK:-no}" = "yes" ] || {
  aws cloudformation delete-stack --region "$REGION" --stack-name "$NET_STACK"
  aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$NET_STACK"; }
# DeletionPolicy: Retain left the DynamoDB table behind on purpose - remove it by hand
aws dynamodb delete-table --region "$REGION" --table-name "$TABLE" >/dev/null && echo "deleted table $TABLE"
