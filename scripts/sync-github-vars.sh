#!/usr/bin/env bash
# Terraform の出力を GitHub の variables に同期する。
#
# 前提:
#   - terraform apply 完了済み
#   - scripts/setup-github.sh 実行済み (Environments が存在すること)
#   - gh CLI ログイン済み、jq インストール済み
set -euo pipefail

cd "$(dirname "$0")/.."

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
OUTPUTS=$(terraform -chdir=terraform output -json)

echo "==> リポジトリ変数 (${REPO})"
gh variable set AWS_REGION --body "$(echo "${OUTPUTS}" | jq -r .aws_region.value)"
gh variable set ECR_REPOSITORY --body "$(echo "${OUTPUTS}" | jq -r .ecr_repository_name.value)"

for ENV in dev staging production; do
  echo "==> environment: ${ENV}"
  E=$(echo "${OUTPUTS}" | jq -r ".environments.value.\"${ENV}\"")
  gh variable set AWS_ROLE_ARN --env "${ENV}" --body "$(echo "${E}" | jq -r .role_arn)"
  gh variable set LAMBDA_FUNCTION_NAME --env "${ENV}" --body "$(echo "${E}" | jq -r .lambda_function_name)"
  gh variable set S3_BUCKET --env "${ENV}" --body "$(echo "${E}" | jq -r .s3_bucket)"
  gh variable set CLOUDFRONT_DISTRIBUTION_ID --env "${ENV}" --body "$(echo "${E}" | jq -r .cloudfront_distribution_id)"
  gh variable set APP_URL --env "${ENV}" --body "$(echo "${E}" | jq -r .app_url)"
done

echo ""
echo "完了。各環境の URL:"
echo "${OUTPUTS}" | jq -r '.environments.value | to_entries[] | "  \(.key): \(.value.app_url)"'
