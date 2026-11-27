#!/usr/bin/env bash
# One command deploys everything:   ./deploy.sh [app-stack] [network-stack]
# Example (first copy):  ./deploy.sh
# Example (second copy): ./deploy.sh cad-sis3-app-copy
set -euo pipefail

APP_STACK="${1:-cad-sis3-app}"
NET_STACK="${2:-cad-sis3-network}"
DESIRED="${DESIRED:-2}"
EXTRA=""; [ -n "${ALARM_EMAIL:-}" ] && EXTRA="AlarmEmail=$ALARM_EMAIL"   # optional: alarm notifications by email
REGION="${AWS_REGION:-eu-central-1}"
TAG="$(git rev-parse --short HEAD)"      # needs at least one git commit
cd "$(dirname "$0")"

echo "== 1/4 network stack: $NET_STACK"
aws cloudformation deploy --region "$REGION" --stack-name "$NET_STACK" \
  --template-file infra/network.yaml --no-fail-on-empty-changeset

echo "== 2/4 app stack with 0 tasks (creates the ECR repository): $APP_STACK"
aws cloudformation deploy --region "$REGION" --stack-name "$APP_STACK" \
  --template-file infra/app.yaml --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides NetworkStackName="$NET_STACK" ImageTag="$TAG" DesiredCount=0 $EXTRA

echo "== 3/4 build and push image $TAG"
REPO_URI="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$APP_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryUri'].OutputValue" --output text)"
REPO_NAME="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$APP_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryName'].OutputValue" --output text)"
if aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" \
     --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "image $TAG already exists (tags are immutable) - skipping push"
else
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "${REPO_URI%%/*}"
  docker build --platform linux/amd64 -t "$REPO_URI:$TAG" app/
  docker push "$REPO_URI:$TAG"
fi

echo "== 4/4 start $DESIRED tasks"
aws cloudformation deploy --region "$REGION" --stack-name "$APP_STACK" \
  --template-file infra/app.yaml --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides NetworkStackName="$NET_STACK" ImageTag="$TAG" DesiredCount="$DESIRED" $EXTRA

aws cloudformation describe-stacks --region "$REGION" --stack-name "$APP_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text
