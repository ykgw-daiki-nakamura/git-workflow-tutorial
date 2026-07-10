#!/usr/bin/env bash
# Terraform の出力を GitHub の variables に同期する。
# 対象の環境は terraform の environments 出力から導出する (local.environments が定義元)。
#
# 前提:
#   - terraform apply 完了済み
#   - scripts/setup-github.sh 実行済み (Environments が存在すること)
#   - gh CLI ログイン済み、jq インストール済み
set -euo pipefail

cd "$(dirname "$0")/.."

# terraform 出力から必須の値を取り出す。
# jq -r は不在キーに対しても終了コード 0 のまま文字列 "null" を出力するため、
# 素直に書くと "null" という値が variables に書き込まれ、スクリプトは成功する。
# -e を付けて null / 不在を非ゼロ終了にし、この場で止める。
jq_required() {
  local filter="$1" json="$2" value
  if ! value=$(jq -er "${filter}" <<< "${json}"); then
    echo "ERROR: terraform の出力に ${filter} が見つかりません" >&2
    echo "       terraform apply は完了していますか?" >&2
    return 1
  fi
  printf '%s' "${value}"
}

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
OUTPUTS=$(terraform -chdir=terraform output -json)

# 値は必ず変数へ代入してから渡すこと。
# gh variable set --body "$(jq_required ...)" と書くと、引数内のコマンド置換の
# 失敗は set -e で捕捉されず、空文字が書き込まれたまま成功してしまう。
echo "==> リポジトリ変数 (${REPO})"
AWS_REGION=$(jq_required '.aws_region.value' "${OUTPUTS}")
ECR_REPOSITORY=$(jq_required '.ecr_repository_name.value' "${OUTPUTS}")
gh variable set AWS_REGION --body "${AWS_REGION}"
gh variable set ECR_REPOSITORY --body "${ECR_REPOSITORY}"

# 環境名は terraform の local.environments を唯一の定義元とし、
# その出力から導出する。ここで列挙すると terraform 側への追加が
# 無言で無視されるため。
ENV_NAMES=$(jq_required '.environments.value | keys[]' "${OUTPUTS}")
mapfile -t ENVIRONMENTS <<< "${ENV_NAMES}"

for ENV_NAME in "${ENVIRONMENTS[@]}"; do
  echo "==> environment: ${ENV_NAME}"
  E=$(jq_required ".environments.value.\"${ENV_NAME}\"" "${OUTPUTS}")

  AWS_ROLE_ARN=$(jq_required '.role_arn' "${E}")
  LAMBDA_FUNCTION_NAME=$(jq_required '.lambda_function_name' "${E}")
  S3_BUCKET=$(jq_required '.s3_bucket' "${E}")
  CLOUDFRONT_DISTRIBUTION_ID=$(jq_required '.cloudfront_distribution_id' "${E}")
  APP_URL=$(jq_required '.app_url' "${E}")

  gh variable set AWS_ROLE_ARN --env "${ENV_NAME}" --body "${AWS_ROLE_ARN}"
  gh variable set LAMBDA_FUNCTION_NAME --env "${ENV_NAME}" --body "${LAMBDA_FUNCTION_NAME}"
  gh variable set S3_BUCKET --env "${ENV_NAME}" --body "${S3_BUCKET}"
  gh variable set CLOUDFRONT_DISTRIBUTION_ID --env "${ENV_NAME}" --body "${CLOUDFRONT_DISTRIBUTION_ID}"
  gh variable set APP_URL --env "${ENV_NAME}" --body "${APP_URL}"
done

echo ""
echo "完了。各環境の URL:"
jq -er '.environments.value | to_entries[] | "  \(.key): \(.value.app_url)"' <<< "${OUTPUTS}"
