# CAD SIS 3 - Order platform as code

Orders API (ECS Fargate behind an ALB) -> SNS topic -> SQS queue (+DLQ) -> idempotent Lambda consumer -> DynamoDB.
Everything is described in CloudFormation. No console clicks are needed.

## Layout
- `infra/network.yaml` - VPC, public and private subnets, one NAT gateway (stack `cad-sis3-network`)
- `infra/app.yaml` - ECR, ECS, ALB, SNS, SQS, DLQs, Lambda, DynamoDB, alarms, log groups (stack `cad-sis3-app`)
- `app/` - the API container (Dockerfile, app.py)
- `deploy.sh`, `destroy.sh` - deploy and delete

## Deploy (one command, region eu-central-1)
```bash
./deploy.sh                        # first copy
./deploy.sh cad-sis3-app-copy      # second copy under a new stack name (reuses the network)
./deploy.sh copy-app copy-net      # fully independent copy, incl. its own network
```
Needs: AWS CLI with credentials, Docker, git (one commit). Image tag = git commit SHA.

## Parameters (infra/app.yaml)
`NetworkStackName`, `Env` (dev|prod), `ImageTag`, `DesiredCount`, `LogRetentionDays`. No secrets exist anywhere in the repo.

## Check
```bash
cfn-lint infra/*.yaml
ALB=$(aws cloudformation describe-stacks --stack-name cad-sis3-app --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
curl -s http://$ALB/health
curl -s -X POST http://$ALB/orders -d '{"customerId":"c42","total":19.5}'
```

## Delete
```bash
./destroy.sh                       # app stack, then network stack, then the retained DynamoDB table
```
