# CI/CD (Practice 7)

Every push to `main` runs `.github/workflows/deploy.yml`:

1. **test** job (no AWS access): `cfn-lint` on both templates, unit tests of the API (`app/test_app.py`).
2. **deploy** job (environment `production`, OIDC role, no stored keys): build the image, tag it with the commit SHA,
   push to ECR (skipped if the tag exists), `aws cloudformation deploy` the `cad-sis3-app` stack with
   `ImageTag=<SHA>`, smoke-test `/health` through the ALB, print the new task definition revision.

One-time bootstrap (CloudShell, IAM user with MFA), see `iam/setup-oidc.sh`:

```bash
OWNER=e1kan REPO=cad-sis3-order-platform OWNER_ID=<id> REPO_ID=<id> ./iam/setup-oidc.sh
```
Then save the printed role ARN as the GitHub repository variable `DEPLOY_ROLE_ARN`.
The stacks `cad-sis3-network` and `cad-sis3-app` must exist first (`./deploy.sh`).
