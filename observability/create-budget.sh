#!/usr/bin/env bash
# Monthly cost budget with email alerts at 50% and 100% (actual spend).
#   EMAIL=you@example.com ./observability/create-budget.sh        (optional: AMOUNT=5 NAME=my-budget)
# Needs billing access for your IAM user. If AccessDenied: ask the root user to enable
# "IAM user and role access to Billing information" (Account page), or use the Pricing Calculator.
set -euo pipefail
: "${EMAIL:?set EMAIL}"
AMOUNT="${AMOUNT:-5}"; NAME="${NAME:-cad-monthly-${AMOUNT}usd}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
cat > /tmp/budget.json <<JSON
{ "BudgetName": "${NAME}", "BudgetType": "COST", "TimeUnit": "MONTHLY",
  "BudgetLimit": { "Amount": "${AMOUNT}", "Unit": "USD" } }
JSON
cat > /tmp/notifications.json <<JSON
[
 { "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 50,  "ThresholdType": "PERCENTAGE" },
   "Subscribers": [ { "SubscriptionType": "EMAIL", "Address": "${EMAIL}" } ] },
 { "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 100, "ThresholdType": "PERCENTAGE" },
   "Subscribers": [ { "SubscriptionType": "EMAIL", "Address": "${EMAIL}" } ] }
]
JSON
aws budgets create-budget --account-id "$ACCOUNT_ID" --budget file:///tmp/budget.json \
  --notifications-with-subscribers file:///tmp/notifications.json
echo "Budget ${NAME} created: ${AMOUNT} USD per month, alerts at 50% and 100%."
