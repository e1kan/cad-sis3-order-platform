#!/usr/bin/env bash
# One-time bootstrap for GitHub Actions -> AWS (run in CloudShell as your IAM user).
#   OWNER=e1kan REPO=cad-sis3-order-platform OWNER_ID=<numeric> REPO_ID=<numeric> ./iam/setup-oidc.sh
# Creates (if missing): the IAM OIDC identity provider for GitHub, and the deploy role.
# The trust policy lets ONE repository and ONE GitHub environment assume the role.
set -euo pipefail
: "${OWNER:?set OWNER}" "${REPO:?set REPO}" "${OWNER_ID:?set OWNER_ID}" "${REPO_ID:?set REPO_ID}"
ENVIRONMENT="${ENVIRONMENT:-production}"
ROLE="${ROLE:-gha-deploy-sis3}"
cd "$(dirname "$0")"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  echo "OIDC provider already exists"
else
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com >/dev/null
  echo "OIDC provider created"
fi

# Repos created after 15 July 2026 use the immutable subject format: repo:OWNER@OWNER_ID/REPO@REPO_ID
SUB="repo:${OWNER}@${OWNER_ID}/${REPO}@${REPO_ID}:environment:${ENVIRONMENT}"
cat > /tmp/trust.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Principal": { "Federated": "${PROVIDER_ARN}" },
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "${SUB}"
      }
    }
  }]
}
JSON
sed "s/__ACCOUNT_ID__/${ACCOUNT_ID}/g" permissions-policy.json > /tmp/permissions.json

if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE" --policy-document file:///tmp/trust.json
else
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document file:///tmp/trust.json \
    --description "GitHub Actions deploy role for SIS 3 (OIDC, no keys)" >/dev/null
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name deploy-sis3 --policy-document file:///tmp/permissions.json

echo "Trusted subject: ${SUB}"
echo "Role ARN (save it as the GitHub variable DEPLOY_ROLE_ARN):"
aws iam get-role --role-name "$ROLE" --query Role.Arn --output text
